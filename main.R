library(here)
library(config)
library(dplyr)
library(lubridate)

source(here::here("R", "data_manipulation.R"))

# Data Extraction ---------------------------------------------------------
message('Start data extraction')
# Set JAVA_HOME, set max. memory, and load rJava library
Sys.setenv(JAVA_HOME = "C:\\Program Files\\Java\\jre1.8.0_171")
options(java.parameters = "-Xmx2g")
library(rJava)

# Output Java version
.jinit()
print(.jcall("java/lang/System", "S", "getProperty", "java.version"))

# Load RJDBC library
library(RJDBC)

# Get credentials
datamnr <-
  config::get("datamnr", file = "C:\\Users\\PoorJ\\Projects\\config.yml")

# Create connection driver
jdbcDriver <-
  JDBC(driverClass = "oracle.jdbc.OracleDriver", classPath = "C:\\Users\\PoorJ\\Desktop\\ojdbc7.jar")

# Open connection: kontakt
jdbcConnection <-
  dbConnect(
    jdbcDriver,
    url = datamnr$server,
    user = datamnr$uid,
    password = datamnr$pwd
  )


# Get SQL scripts
readQuery <-
  function(file)
    paste(readLines(file, warn = FALSE), collapse = "\n")

# Fetch data
query_backlog <- readQuery(here::here("SQL", "get_backlog.sql"))
t_backlog <- dbGetQuery(jdbcConnection, query_backlog)

query_fte <- readQuery(here::here("SQL", "get_fte.sql"))
t_fte <- dbGetQuery(jdbcConnection, query_fte)

t_mnap <- dbGetQuery(jdbcConnection, 'select * from t_mnap')
t_mnap <- t_mnap %>% mutate(IDOSZAK = ymd_hms(IDOSZAK))


# Close db connection: kontakt
dbDisconnect(jdbcConnection)



# Data Cleaning and Transformations ---------------------------------------
# Backlog
message('Start cleaning backlog table')
t_backlog_tr <- t_backlog %>%
  filter(CLASS_SHORT %in% c("INC", "SDEV", "DEV", "RFC")) %>%
  mutate(
    CREATED = ymd_hms(CREATED),
    CLOSED = ymd_hms(CLOSED),
    START = as.Date(floor_date(CREATED), units = "month"),
    END = as.Date(floor_date(CLOSED), units = "month"),
    TICKET = case_when(
      CLASSIFICATION == "Adatkorrekció (RFC)" | CLASSIFICATION == "Adatlekérdezési igény (RFC)" ~ "Data correction/query",
      CLASS_SHORT == "INC" ~ "Defect",
      CLASS_SHORT == "SDEV" | (CLASS_SHORT == "DEV" & VIP == 1 & CREATED <= as.Date('2019-07-05')) ~ "Development Small",
      TRUE ~ "Development"
    ),
    APPGROUP = case_when(
      stringr::str_detect(APPLICATION_GROUP_CONCAT, "/") ~ "Z_Közös",
      TRUE ~ APPLICATION_GROUP_CONCAT
    ),
    APPSINGLE = case_when(
      stringr::str_detect(APPLICATION, ";") ~ "Multiple",
      TRUE ~ "Single"
    )
  )


# FTE
message('Start cleaning FTE table')
t_fte_tr <- t_fte %>%
  filter(CLASS_SHORT %in% c("INC", "SDEV", "DEV", "RFC")) %>%
  mutate(
    CREATED = ymd_hms(CREATED),
    TICKET = case_when(
      CLASSIFICATION == "Adatkorrekció (RFC)" | CLASSIFICATION == "Adatlekérdezési igény (RFC)" ~ "Data correction/query",
      CLASS_SHORT == "INC" ~ "Defect",
      CLASS_SHORT == "SDEV" | (CLASS_SHORT == "DEV" & VIP == 1 & CREATED <= as.Date('2019-07-05')) ~ "Development Small",
      TRUE ~ "Development"
    ),
    APPGROUP = case_when(
      stringr::str_detect(APPLICATION_GROUP_CONCAT, "/") ~ "Z_Közös",
      TRUE ~ APPLICATION_GROUP_CONCAT
    ),
    APPSINGLE = case_when(
      stringr::str_detect(APPLICATION, ";") ~ "Multiple",
      TRUE ~ "Single"
    )
  )


# Backlog Size ---------------------------------------------------------
message("Start backlog aggregation for ticket types")
t_cutpoints <- tibble(CUTPOINT = seq(floor_date(as.Date(ymd(Sys.Date()) - years(2)), unit = "month"), Sys.Date(), by = "1 month"))
t_backlog_ticket <- get_backlog(t_backlog_tr, t_cutpoints, TICKET)

write.csv(t_backlog_ticket, here::here("Data", "t_backlog_ticket.csv"), row.names = FALSE)



# Throughput Volume -------------------------------------------------------
message("Start throughput volume aggregation for ticket types")
t_throughput_ticket <- t_backlog_tr %>%
  # Transform data
  filter(!is.na(CLOSED)) %>%
  filter(CLOSED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
    CLOSED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  mutate(CLOSED_MONTH = as.Date(floor_date(CLOSED, unit = "month"))) %>%
  group_by(CLOSED_MONTH, TICKET) %>%
  summarize(THROUGHPUT = n()) %>%
  ungroup()

write.csv(t_throughput_ticket, here::here("Data", "t_throughput_ticket.csv"), row.names = FALSE)



# Throughput Time ---------------------------------------------------------
message("Start throughput time aggregation for ticket types")
t_throughputtime_ticket <- t_backlog_tr %>%
  # Transform data
  filter(!is.na(CLOSED)) %>%
  filter(CLOSED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
           CLOSED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  mutate(CLOSED_MONTH = as.Date(floor_date(CLOSED, unit = "month")),
         THROUGHPUT_TIME = difftime(CLOSED, CREATED ,units="days")) %>%
  group_by(CLOSED_MONTH, TICKET) %>%
  summarize(THROUGHPUT_TIME = round(median(THROUGHPUT_TIME), 1)) %>%
  ungroup()

write.csv(t_throughputtime_ticket, here::here("Data", "t_throughputtime_ticket.csv"), row.names = FALSE)




# FTE and Efficiency ------------------------------------------------------
message("Start FTE aggregation for ticket types")
t_fte_ticket <- t_fte_tr %>%
  filter(!is.na(MONTH_WORKTIMESHEET)) %>%
  mutate(MONTH_WORKTIMESHEET = ymd_hms(MONTH_WORKTIMESHEET)) %>% 
  filter(MONTH_WORKTIMESHEET >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
           MONTH_WORKTIMESHEET < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  group_by(MONTH_WORKTIMESHEET, TICKET) %>% 
  summarize(HOURS_WORKTIMESHEET = sum(HOURS_WORKTIMESHEET),
            TICKET_NUM = n()) %>% 
  ungroup() %>% 
  left_join(t_mnap, by = c("MONTH_WORKTIMESHEET" = "IDOSZAK")) %>% 
  mutate(FTE = round(HOURS_WORKTIMESHEET/7/MNAP, 2),
         FTE_NORM = round(FTE/TICKET_NUM, 2)) 

write.csv(t_fte_ticket, here::here("Data", "t_fte_ticket.csv"), row.names = FALSE)
  
  


# Teams Backlog -----------------------------------------------------------
message("Start team backlog aggregation for ticket types")
t_backlog_ticket_team <- get_backlog(t_backlog_tr, t_cutpoints, TICKET, APPGROUP)

write.csv(t_backlog_ticket_team, here::here("Data", "t_backlog_ticket_team.csv"), row.names = FALSE)




# Teams Throughput --------------------------------------------------------
message("Start team throughput aggregation for ticket types")
t_throughput_ticket_team <- t_backlog_tr %>%
  # Transform data
  filter(!is.na(CLOSED)) %>%
  filter(CLOSED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
           CLOSED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  mutate(CLOSED_MONTH = as.Date(floor_date(CLOSED, unit = "month"))) %>%
  group_by(CLOSED_MONTH, TICKET, APPGROUP) %>%
  summarize(THROUGHPUT = n()) %>%
  ungroup()

write.csv(t_throughput_ticket_team, here::here("Data", "t_throughput_ticket_team.csv"), row.names = FALSE)




# Teams Throughput Time ---------------------------------------------------
message("Start team throughput time aggregation for ticket types")
t_throughputtime_ticket_team <- t_backlog_tr %>%
  # Transform data
  filter(!is.na(CLOSED)) %>%
  filter(CLOSED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
           CLOSED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  mutate(CLOSED_MONTH = as.Date(floor_date(CLOSED, unit = "month")),
         THROUGHPUT_TIME = difftime(CLOSED, CREATED ,units="days")) %>%
  group_by(CLOSED_MONTH, TICKET, APPGROUP) %>%
  summarize(THROUGHPUT_TIME = round(median(THROUGHPUT_TIME), 1)) %>%
  ungroup()

write.csv(t_throughputtime_ticket_team, here::here("Data", "t_throughputtime_ticket_team.csv"), row.names = FALSE)




# Teams Resources ---------------------------------------------------------
message("Start team resources aggregation for ticket types")
t_fte_ticket_team <- t_fte_tr %>%
  filter(!is.na(MONTH_WORKTIMESHEET)) %>%
  mutate(MONTH_WORKTIMESHEET = ymd_hms(MONTH_WORKTIMESHEET)) %>% 
  filter(MONTH_WORKTIMESHEET >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
           MONTH_WORKTIMESHEET < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  group_by(MONTH_WORKTIMESHEET, TICKET, APPGROUP) %>% 
  summarize(HOURS_WORKTIMESHEET = sum(HOURS_WORKTIMESHEET),
            TICKET_NUM = n()) %>% 
  ungroup() %>% 
  left_join(t_mnap, by = c("MONTH_WORKTIMESHEET" = "IDOSZAK")) %>% 
  mutate(FTE = round(HOURS_WORKTIMESHEET/7/MNAP, 2),
         FTE_NORM = round(FTE/TICKET_NUM, 2)) 

write.csv(t_fte_ticket_team, here::here("Data", "t_fte_ticket_team.csv"), row.names = FALSE)






