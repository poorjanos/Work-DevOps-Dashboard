library(here)
library(config)
library(dplyr)
library(lubridate)

source(here::here("R", "data_manipulation.R"))

# Data Extraction ---------------------------------------------------------
message('Start data extraction')
# Set JAVA_HOME, set max. memory, and load rJava library
java_version = config::get("java_version", file = "C:\\Users\\PoorJ\\Projects\\config.yml")
Sys.setenv(JAVA_HOME = java_version$JAVA_HOME)
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



# Fetch data
t_backlog <- dbGetQuery(jdbcConnection, "select * from t_isd_tickets")

t_dev_milestones <- dbGetQuery(jdbcConnection, "select * from t_dev_milestones")

t_fte <- dbGetQuery(jdbcConnection, "select * from t_isd_worktimesheet")

t_mnap <- dbGetQuery(jdbcConnection, 'select * from t_mnap')
t_mnap <- t_mnap %>% mutate(IDOSZAK = ymd_hms(IDOSZAK))


# Close db connection: kontakt
dbDisconnect(jdbcConnection)



# Data Cleaning and Transformations ---------------------------------------
# Backlog
message('Start cleaning backlog table')
t_backlog_tr <- t_backlog %>%
  mutate(
    CREATED = ymd_hms(CREATED),
    CLOSED = ymd_hms(CLOSED),
    START = as.Date(floor_date(CREATED)),
    END = as.Date(floor_date(CLOSED)),
    CREATED_MONTH = paste0(
      substr(as.Date(floor_date(CREATED, unit = "month")), 1, 4),
      "/",
      substr(as.Date(floor_date(CREATED, unit = "month")), 6, 7)
    ),
    CLOSED_MONTH = paste0(
      substr(as.Date(floor_date(CLOSED, unit = "month")), 1, 4),
      "/",
      substr(as.Date(floor_date(CLOSED, unit = "month")), 6, 7)
    )
  )

message('Start cleaning dev_milestones table')
t_dev_milestones_tr <- t_dev_milestones %>%
  mutate(
    CREATED = ymd_hms(CREATED),
    CLOSED = ymd_hms(CLOSED),
    START = as.Date(floor_date(CREATED)),
    END = as.Date(floor_date(CLOSED)),
    CREATED_MONTH = paste0(
      substr(as.Date(floor_date(CREATED, unit = "month")), 1, 4),
      "/",
      substr(as.Date(floor_date(CREATED, unit = "month")), 6, 7)
    ),
    CLOSED_MONTH = paste0(
      substr(as.Date(floor_date(CLOSED, unit = "month")), 1, 4),
      "/",
      substr(as.Date(floor_date(CLOSED, unit = "month")), 6, 7)
    )
  )


#FTE
message('Start cleaning FTE table')
t_fte_tr <- t_fte %>%
  filter(complete.cases(HOURS_WORKTIMESHEET)) %>% 
  mutate(
    CREATED = ymd_hms(CREATED),
    CLOSED = ymd_hms(CLOSED),
    TARGETDAY = ymd_hms(TARGETDAY),
    TARGETDAY_TO_MONTH = floor_date(TARGETDAY, unit = "month"),
    TARGET_MONTH = paste0(
      substr(as.Date(floor_date(TARGETDAY, unit = "month")), 1, 4),
      "/",
      substr(as.Date(floor_date(TARGETDAY, unit = "month")), 6, 7)
    )
  )

  

# Tickets Open ---------------------------------------------------------
message("Start backlog aggregation for ticket types")
t_cutpoints <- tibble(CUTPOINT = seq(floor_date(as.Date(ymd(Sys.Date()) - years(2)),
                                                unit = "month"), Sys.Date(),
                                     by = "1 month"))

t_ticket_open <- get_backlog(t_backlog_tr, t_cutpoints, TICKET)

write.csv(t_ticket_open, here::here("Data", "t_ticket_open.csv"), row.names = FALSE)



# Tickets Started -------------------------------------------------------
message("Start new ticket volume aggregation for ticket types")
t_ticket_started <- t_backlog_tr %>%
  # Transform data
  filter(!is.na(CREATED)) %>%
  filter(CREATED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
    CREATED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  group_by(CREATED_MONTH, TICKET) %>%
  summarize(COUNT = n()) %>%
  ungroup()

write.csv(t_ticket_started, here::here("Data", "t_ticket_started.csv"), row.names = FALSE)



# Tickets Closed -------------------------------------------------------
message("Start throughput volume aggregation for ticket types")
t_ticket_closed <- t_backlog_tr %>%
  # Transform data
  filter(!is.na(CLOSED)) %>%
  filter(CLOSED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
    CLOSED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  group_by(CLOSED_MONTH, TICKET) %>%
  summarize(COUNT = n()) %>%
  ungroup()

write.csv(t_ticket_closed, here::here("Data", "t_ticket_closed.csv"), row.names = FALSE)



# Total Lead Time ---------------------------------------------------------
message("Start lead time aggregation for ticket types")
t_leadtime_ticket <- t_backlog_tr %>%
  # Transform data
  filter(!is.na(CLOSED)) %>%
  filter(CLOSED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
    CLOSED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  mutate(LEADTIME = difftime(CLOSED, CREATED, units = "days")) %>%
  group_by(CLOSED_MONTH, TICKET) %>%
  summarize(LEADTIME = round(median(LEADTIME), 1)) %>%
  ungroup()

write.csv(t_leadtime_ticket, here::here("Data", "t_leadtime_ticket.csv"), row.names = FALSE)



# Development Lead Time Without Voting Times-----------------------------
message("Start net lead time aggregation for dev tickets")
t_leadtime_dev_net <- t_dev_milestones_tr %>%
  # Transform data
  filter(!is.na(CLOSED)) %>%
  filter(CLOSED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
    CLOSED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  group_by(CLOSED_MONTH, TICKET) %>%
  summarize(LEADTIME_NET = round(median(START_CLOSE_NET_DAYS), 1),
            NET_DAYS = sum(START_CLOSE_NET_DAYS),
            VOTING_DAYS = sum(START_CLOSE_DAYS-START_CLOSE_NET_DAYS)) %>%
  ungroup() %>% 
  mutate(VOTING_RATIO = round(VOTING_DAYS/(NET_DAYS+VOTING_DAYS), 4))

write.csv(t_leadtime_dev_net, here::here("Data", "t_leadtime_dev_net.csv"), row.names = FALSE)






# FTE and Unit FTE --------------------------------------------------------
message("Start FTE aggregation for ticket types")
t_fte_ticket <- t_fte_tr %>%
  filter(TARGETDAY >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
           TARGETDAY < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  group_by(TARGETDAY_TO_MONTH, TARGET_MONTH, TICKET) %>%
  summarize(HOURS_WORKTIMESHEET = sum(HOURS_WORKTIMESHEET),
            TICKET_NUM = n()) %>%
  ungroup() %>%
  left_join(t_mnap, by = c("TARGETDAY_TO_MONTH" = "IDOSZAK")) %>%
  mutate(FTE = round(HOURS_WORKTIMESHEET/7/MNAP, 2),
         FTE_NORM = round(FTE/TICKET_NUM, 4)) %>% 
  group_by(TARGET_MONTH) %>%
  mutate(FTE_PCT = FTE / sum(FTE)) %>%
  ungroup()
  

write.csv(t_fte_ticket, here::here("Data", "t_fte_ticket.csv"), row.names = FALSE)



# Dev FTE  ----------------------------------------------------------------
message("Start dev FTE phases aggregation for ticket types")
t_fte_phases <- t_fte_tr %>%
  filter(stringr::str_detect(TICKET, "Development")) %>%
  filter(TARGETDAY >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
    TARGETDAY < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  tidyr::replace_na(list(ACTIONTYPEGROUP = "Ismeretlen")) %>%
  mutate(ACTIONTYPEGROUP = case_when(
    ACTIONTYPEGROUP == "Elemzés, egyeztetés, becslés, tervezés, specifikáció készítés" ~ "Elemzés",
    ACTIONTYPEGROUP == "Megbeszélés, Oktatás, Tréning, Tájékoztatók" ~ "Megbeszélés/oktatás",
    ACTIONTYPEGROUP == "Vezetõi / projektvezetõi / HR / adminisztrációs feladat" ~ "Vezetõi/admin",
    TRUE ~ ACTIONTYPEGROUP
  )) %>%
  mutate(ACTIONTYPEGROUP = forcats::fct_lump(factor(ACTIONTYPEGROUP), n = 7, other_level = "Egyéb")) %>%
  group_by(TARGETDAY_TO_MONTH, TARGET_MONTH, TICKET, ACTIONTYPEGROUP) %>%
  summarize(
    HOURS_WORKTIMESHEET = sum(HOURS_WORKTIMESHEET),
    TICKET_NUM = n()
  ) %>%
  ungroup() %>%
  left_join(t_mnap, by = c("TARGETDAY_TO_MONTH" = "IDOSZAK")) %>%
  mutate(
    FTE = round(HOURS_WORKTIMESHEET / 7 / MNAP, 2),
    FTE_NORM = round(FTE / TICKET_NUM, 4)
  ) %>%
  group_by(TARGET_MONTH, TICKET) %>%
  mutate(FTE_PCT = FTE / sum(FTE)) %>%
  ungroup()

write.csv(t_fte_phases, here::here("Data", "t_fte_phases.csv"), row.names = FALSE)



# Teams New Ticket -----------------------------------------------------------
message("Start team new ticket aggregation for ticket types")
t_nb_ticket_team <- t_backlog_tr %>%
  # Transform data
  filter(!is.na(CREATED)) %>%
  filter(CREATED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
           CREATED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  group_by(CREATED_MONTH, TICKET, APPGROUP) %>%
  summarize(COUNT = n()) %>%
  ungroup()

write.csv(t_nb_ticket_team, here::here("Data", "t_nb_ticket_team.csv"), row.names = FALSE)



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
  group_by(CLOSED_MONTH, TICKET, APPGROUP) %>%
  summarize(COUNT = n()) %>%
  ungroup()

write.csv(t_throughput_ticket_team, here::here("Data", "t_throughput_ticket_team.csv"), row.names = FALSE)




# Teams Throughput Time ---------------------------------------------------
message("Start team throughput time aggregation for ticket types")
t_throughputtime_ticket_team <- t_backlog_tr %>%
  # Transform data
  filter(!is.na(CLOSED)) %>%
  filter(CLOSED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
           CLOSED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  mutate(THROUGHPUT_TIME = difftime(CLOSED, CREATED ,units="days")) %>%
  group_by(CLOSED_MONTH, TICKET, APPGROUP) %>%
  summarize(THROUGHPUT_TIME = round(median(THROUGHPUT_TIME), 1)) %>%
  ungroup()

write.csv(t_throughputtime_ticket_team, here::here("Data", "t_throughputtime_ticket_team.csv"), row.names = FALSE)




# Teams FTE ---------------------------------------------------------
message("Start team resources aggregation for ticket types")
t_fte_ticket_team <- t_fte_tr %>%
  filter(!is.na(TARGETDAY)) %>%
  filter(TARGETDAY >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
           TARGETDAY < floor_date(ymd(Sys.Date()), unit = "month")) %>%
  group_by(TARGETDAY_TO_MONTH, TARGET_MONTH, TICKET, USERORG_WORKTIMESHEET) %>%
  summarize(HOURS_WORKTIMESHEET = sum(HOURS_WORKTIMESHEET),
            TICKET_NUM = n()) %>%
  ungroup() %>%
  left_join(t_mnap, by = c("TARGETDAY_TO_MONTH" = "IDOSZAK")) %>%
  mutate(FTE = round(HOURS_WORKTIMESHEET/7/MNAP, 2),
         FTE_NORM = round(FTE/TICKET_NUM, 4))

write.csv(t_fte_ticket_team, here::here("Data", "t_fte_ticket_team.csv"), row.names = FALSE)




# Leader Board Throughput Open ------------------------------------------
message("Start Leader Board Throughput Closed aggregation for tickets")
t_lb_tp_open <- t_backlog_tr %>%
  filter(is.na(CLOSED)) %>%
  filter(!is.na(LAST_EVENT)) %>%
  select(CASE_ID, ISSUE_TITLE, CREATED, TICKET, LAST_EVENT, LAST_EVENT_DATE, APPGROUP) %>%
  mutate(DAYS_OPEN = difftime(Sys.Date(), CREATED, units="days")) %>%
  group_by(TICKET) %>%
  top_n(10, row_number(DAYS_OPEN)) %>%
  ungroup() %>%
  mutate(DAYS_OPEN = round(DAYS_OPEN, 0)) %>%
  arrange(TICKET, desc(DAYS_OPEN)) %>%
  select(TICKET, CASE_ID, ISSUE_TITLE, CREATED, TEAM = APPGROUP, DAYS_OPEN, LAST_EVENT, LAST_EVENT_DATE)

write.csv(t_lb_tp_open, here::here("Data", "t_lb_tp_open.csv"), row.names = FALSE)


# Leader Board FTE  ------------------------------------------
message("Start Leader Board FTE aggregation for tickets")
t_lb_fte_open <- t_fte_tr %>%
  filter(is.na(CLOSED)) %>%
  group_by(TICKET, CASE_ID, ISSUE_TITLE, CREATED, TEAM = APPGROUP) %>%
  summarize(TOTAL_HOURS = sum(HOURS_WORKTIMESHEET)) %>%
  ungroup() %>%
  mutate(MONTHS_OPEN = as.numeric(difftime(Sys.Date(), CREATED, units= "days") / 30),
         FTE_PER_MONTH = round(TOTAL_HOURS/MONTHS_OPEN/7/21, 2)) %>%
  group_by(TICKET) %>%
  top_n(10, row_number(TOTAL_HOURS)) %>%
  ungroup() %>%
  mutate(TOTAL_HOURS = round(TOTAL_HOURS, 0)) %>%
  arrange(TICKET, desc(TOTAL_HOURS)) %>%
  select(-MONTHS_OPEN)

write.csv(t_lb_fte_open, here::here("Data", "t_lb_fte_open.csv"), row.names = FALSE)






# Conformance Analysis Issue List -----------------------------------------
message("Start Conformance Analysis issue list")
t_conf <- t_dev_milestones_tr %>%
  filter(!is.na(CLOSED) & CLASS_SHORT != "RFC") %>%
  select(TICKET, CASE_ID, ISSUE_TITLE, CREATED, CLOSED, STEPS = DISTINCT_STEPS, ADMIN_STEP, CONFORM) %>%
  mutate(CONFORM = case_when(CONFORM == "I" ~ "Conform",
                             TRUE ~ "Deviant")) %>% 
  arrange(TICKET, CREATED)

write.csv(t_conf, here::here("Data", "t_conf.csv"), row.names = FALSE)



# Conformance Analysis Aggregation ----------------------------------------
message("Start Conformance Analysis aggregation")
t_conf_agg <- t_dev_milestones_tr %>%
  filter(!is.na(CLOSED) & CLASS_SHORT != "RFC") %>%
  mutate(CREATED_YEAR = substr(CREATED_MONTH, 1, 4)) %>% 
  mutate(CONFORM = case_when(
    CONFORM == "I" ~ "Conform",
    TRUE ~ "Deviant"
  )) %>%
  group_by(CREATED_YEAR, CREATED_MONTH, TICKET, CONFORM) %>%
  summarize(COUNT = n()) %>%
  ungroup() %>%
  # Need to use spread to fill 0 for missing months to make cumulative time-series complete
  tidyr::spread(CONFORM, COUNT, fill = 0) %>%
  # Need to gather to be able to input to ggplot geom_bar(aes(fill=))
  tidyr::gather(key = CONFORM, value = COUNT, -TICKET, -CREATED_YEAR, -CREATED_MONTH) %>%
  arrange(TICKET, CREATED_YEAR, CREATED_MONTH) %>%
  group_by(TICKET) %>%
  mutate(CUMULATIVE_COUNT = cumsum(COUNT)) %>%
  ungroup()

write.csv(t_conf_agg, here::here("Data", "t_conf_agg.csv"), row.names = FALSE)


# Conformance Lead Times --------------------------------------------------
message("Start Conformance Analysis aggregation")
t_conf_agg_lt <- t_dev_milestones_tr %>%
  filter(!is.na(CLOSED) & CLASS_SHORT != "RFC" & CONFORM == "I") %>%
  group_by(CREATED_MONTH, TICKET) %>%
  summarize(PRE_DEMAND_DAYS = round(median(PRE_DEMAND_DAYS), 4),
            DEMAND_DAYS = round(median(DEMAND_DAYS), 4),
            RELEASE_DAYS = round(median(RELEASE_DAYS),4))%>%
  ungroup() %>% 
  tidyr::gather(key = SEGMENT, value = LEAD_TIME, -CREATED_MONTH, -TICKET) %>% 
  mutate(SEGMENT = factor(SEGMENT, levels = c("RELEASE_DAYS", "DEMAND_DAYS", "PRE_DEMAND_DAYS")))

write.csv(t_conf_agg_lt, here::here("Data", "t_conf_agg_lt.csv"), row.names = FALSE)





