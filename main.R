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
    END = as.Date(floor_date(CLOSED))
  )


message('Start cleaning dev_milestones table')
t_dev_milestones_tr <- t_dev_milestones %>%
  mutate(
    CREATED = ymd_hms(CREATED),
    CLOSED = ymd_hms(CLOSED),
    START = as.Date(floor_date(CREATED)),
    END = as.Date(floor_date(CLOSED))
  )

# FTE
# message('Start cleaning FTE table')
# t_fte_tr <- t_fte %>%
#   filter(CLASS_SHORT %in% c("INC", "SDEV", "DEV", "RFC")) %>%
#   mutate(
#     CREATED = ymd_hms(CREATED),
#     TICKET = case_when(
#       CLASSIFICATION == "Adatkorrekció (RFC)" | CLASSIFICATION == "Adatlekérdezési igény (RFC)" ~ "Data correction/query",
#       CLASS_SHORT == "INC" ~ "Defect",
#       CLASS_SHORT == "SDEV" | (CLASS_SHORT == "DEV" & VIP == 1 & CREATED <= as.Date('2019-07-05')) ~ "Development Small",
#       TRUE ~ "Development"
#     ),
#     APPGROUP = case_when(
#       stringr::str_detect(APPLICATION_GROUP_CONCAT, "/") ~ "Z_Közös",
#       TRUE ~ APPLICATION_GROUP_CONCAT
#     ),
#     APPSINGLE = case_when(
#       stringr::str_detect(APPLICATION, ";") ~ "Multiple",
#       TRUE ~ "Single"
#     )
#   )


# Dev FTE phases
# message('Start cleaning dev FTE phases table')
# t_dev_fte_phases_tr <-  t_dev_fte_phases %>%
#   mutate(
#     CREATED = ymd_hms(CREATED),
#     CREATED_WORKTIMESHEET = ymd_hms(CREATED_WORKTIMESHEET),
#     TICKET = case_when(
#       CLASSIFICATION == "Adatkorrekció (RFC)" | CLASSIFICATION == "Adatlekérdezési igény (RFC)" ~ "Data correction/query",
#       CLASS_SHORT == "INC" ~ "Defect",
#       CLASS_SHORT == "SDEV" | (CLASS_SHORT == "DEV" & VIP == 1 & CREATED <= as.Date('2019-07-05')) ~ "Development Small",
#       TRUE ~ "Development"
#     ),
#     APPGROUP = case_when(
#       stringr::str_detect(APPLICATION_GROUP_CONCAT, "/") ~ "Z_Közös",
#       TRUE ~ APPLICATION_GROUP_CONCAT
#     ),
#     APPSINGLE = case_when(
#       stringr::str_detect(APPLICATION, ";") ~ "Multiple",
#       TRUE ~ "Single"
#     )
#   )
  
  

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
  mutate(CREATED_MONTH = paste0(
    substr(as.Date(floor_date(CREATED, unit = "month")), 1, 4),
    "/",
    substr(as.Date(floor_date(CREATED, unit = "month")), 6, 7)
  )) %>%
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
  mutate(CLOSED_MONTH = paste0(
    substr(as.Date(floor_date(CLOSED, unit = "month")), 1, 4),
    "/",
    substr(as.Date(floor_date(CLOSED, unit = "month")), 6, 7)
  )) %>%
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
  mutate(
    CLOSED_MONTH = paste0(
      substr(as.Date(floor_date(CLOSED, unit = "month")), 1, 4),
      "/",
      substr(as.Date(floor_date(CLOSED, unit = "month")), 6, 7)
    ),
    LEADTIME = difftime(CLOSED, CREATED, units = "days")
  ) %>%
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
  mutate(
    CLOSED_MONTH = paste0(
      substr(as.Date(floor_date(CLOSED, unit = "month")), 1, 4),
      "/",
      substr(as.Date(floor_date(CLOSED, unit = "month")), 6, 7)
    )
  ) %>%
  group_by(CLOSED_MONTH, TICKET) %>%
  summarize(LEADTIME_NET = round(median(START_CLOSE_NET_DAYS), 1),
            NET_DAYS = sum(START_CLOSE_NET_DAYS),
            VOTING_DAYS = sum(START_CLOSE_DAYS-START_CLOSE_NET_DAYS)) %>%
  ungroup() %>% 
  mutate(VOTING_RATIO = round(VOTING_DAYS/(NET_DAYS+VOTING_DAYS), 4))

write.csv(t_leadtime_dev_net, here::here("Data", "t_leadtime_dev_net.csv"), row.names = FALSE)


# # FTE and Unit FTE --------------------------------------------------------
# message("Start FTE aggregation for ticket types")
# t_fte_ticket <- t_fte_tr %>%
#   filter(!is.na(MONTH_WORKTIMESHEET)) %>%
#   mutate(MONTH_WORKTIMESHEET = ymd_hms(MONTH_WORKTIMESHEET)) %>% 
#   filter(MONTH_WORKTIMESHEET >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
#            MONTH_WORKTIMESHEET < floor_date(ymd(Sys.Date()), unit = "month")) %>%
#   group_by(MONTH_WORKTIMESHEET, TICKET) %>% 
#   summarize(HOURS_WORKTIMESHEET = sum(HOURS_WORKTIMESHEET),
#             TICKET_NUM = n()) %>% 
#   ungroup() %>% 
#   left_join(t_mnap, by = c("MONTH_WORKTIMESHEET" = "IDOSZAK")) %>% 
#   mutate(FTE = round(HOURS_WORKTIMESHEET/7/MNAP, 2),
#          FTE_NORM = round(FTE/TICKET_NUM, 4)) 
# 
# write.csv(t_fte_ticket, here::here("Data", "t_fte_ticket.csv"), row.names = FALSE)
#   
#   
# 
# # Teams New Ticket -----------------------------------------------------------
# message("Start team new ticket aggregation for ticket types")
# t_nb_ticket_team <- t_backlog_tr %>%
#   # Transform data
#   filter(!is.na(CREATED)) %>%
#   filter(CREATED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
#            CREATED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
#   mutate(CREATED_MONTH = as.Date(floor_date(CREATED, unit = "month"))) %>%
#   group_by(CREATED_MONTH, TICKET, APPGROUP) %>%
#   summarize(NEW_TICKET = n()) %>%
#   ungroup()
# 
# write.csv(t_nb_ticket_team, here::here("Data", "t_nb_ticket_team.csv"), row.names = FALSE)
# 
# 
# 
# # Teams Backlog -----------------------------------------------------------
# message("Start team backlog aggregation for ticket types")
# t_backlog_ticket_team <- get_backlog(t_backlog_tr, t_cutpoints, TICKET, APPGROUP)
# 
# write.csv(t_backlog_ticket_team, here::here("Data", "t_backlog_ticket_team.csv"), row.names = FALSE)
# 
# 
# 
# 
# # Teams Throughput --------------------------------------------------------
# message("Start team throughput aggregation for ticket types")
# t_throughput_ticket_team <- t_backlog_tr %>%
#   # Transform data
#   filter(!is.na(CLOSED)) %>%
#   filter(CLOSED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
#            CLOSED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
#   mutate(CLOSED_MONTH = as.Date(floor_date(CLOSED, unit = "month"))) %>%
#   group_by(CLOSED_MONTH, TICKET, APPGROUP) %>%
#   summarize(THROUGHPUT = n()) %>%
#   ungroup()
# 
# write.csv(t_throughput_ticket_team, here::here("Data", "t_throughput_ticket_team.csv"), row.names = FALSE)
# 
# 
# 
# 
# # Teams Throughput Time ---------------------------------------------------
# message("Start team throughput time aggregation for ticket types")
# t_throughputtime_ticket_team <- t_backlog_tr %>%
#   # Transform data
#   filter(!is.na(CLOSED)) %>%
#   filter(CLOSED >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
#            CLOSED < floor_date(ymd(Sys.Date()), unit = "month")) %>%
#   mutate(CLOSED_MONTH = as.Date(floor_date(CLOSED, unit = "month")),
#          THROUGHPUT_TIME = difftime(CLOSED, CREATED ,units="days")) %>%
#   group_by(CLOSED_MONTH, TICKET, APPGROUP) %>%
#   summarize(THROUGHPUT_TIME = round(median(THROUGHPUT_TIME), 1)) %>%
#   ungroup()
# 
# write.csv(t_throughputtime_ticket_team, here::here("Data", "t_throughputtime_ticket_team.csv"), row.names = FALSE)
# 
# 
# 
# 
# # Teams FTE ---------------------------------------------------------
# message("Start team resources aggregation for ticket types")
# t_fte_ticket_team <- t_fte_tr %>%
#   filter(!is.na(MONTH_WORKTIMESHEET)) %>%
#   mutate(MONTH_WORKTIMESHEET = ymd_hms(MONTH_WORKTIMESHEET)) %>% 
#   filter(MONTH_WORKTIMESHEET >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
#            MONTH_WORKTIMESHEET < floor_date(ymd(Sys.Date()), unit = "month")) %>%
#   group_by(MONTH_WORKTIMESHEET, TICKET, USERORG_WORKTIMESHEET) %>% 
#   summarize(HOURS_WORKTIMESHEET = sum(HOURS_WORKTIMESHEET),
#             TICKET_NUM = n()) %>% 
#   ungroup() %>% 
#   left_join(t_mnap, by = c("MONTH_WORKTIMESHEET" = "IDOSZAK")) %>% 
#   mutate(FTE = round(HOURS_WORKTIMESHEET/7/MNAP, 2),
#          FTE_NORM = round(FTE/TICKET_NUM, 4)) 
# 
# write.csv(t_fte_ticket_team, here::here("Data", "t_fte_ticket_team.csv"), row.names = FALSE)
# 
# 
# 
# 
# # Dev FTE  ----------------------------------------------------------------
# message("Start dev FTE phases aggregation for ticket types")
# t_fte_phases <- t_dev_fte_phases_tr %>%
#   mutate(
#     MONTH_WORKTIMESHEET = floor_date(CREATED_WORKTIMESHEET, unit = "month"),
#     FTE_BREAKDOWN = case_when(
#       !is.na(ABORTED) ~ "Aborted",
#       is.na(ABORTED) & is.na(PHASE) ~ "Demand",
#       TRUE ~ PHASE
#     )
#   ) %>%
#   filter(MONTH_WORKTIMESHEET >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
#     MONTH_WORKTIMESHEET < floor_date(ymd(Sys.Date()), unit = "month")) %>%
#   group_by(MONTH_WORKTIMESHEET, FTE_BREAKDOWN) %>%
#   summarize(
#     HOURS_WORKTIMESHEET = sum(HOURS_WORKTIMESHEET),
#     TICKET_NUM = n()
#   ) %>%
#   ungroup() %>%
#   left_join(t_mnap, by = c("MONTH_WORKTIMESHEET" = "IDOSZAK")) %>%
#   mutate(
#     FTE = round(HOURS_WORKTIMESHEET / 7 / MNAP, 2),
#     FTE_NORM = round(FTE / TICKET_NUM, 4)
#   )
# 
# write.csv(t_fte_phases, here::here("Data", "t_fte_phases.csv"), row.names = FALSE)
# 
# 
# 
# # Teams Dev FTE  ----------------------------------------------------------------
# message("Start teams dev FTE phases aggregation for ticket types")
# t_fte_phases_team <- t_dev_fte_phases_tr %>%
#   mutate(
#     MONTH_WORKTIMESHEET = floor_date(CREATED_WORKTIMESHEET, unit = "month"),
#     FTE_BREAKDOWN = case_when(
#       !is.na(ABORTED) ~ "Aborted",
#       is.na(ABORTED) & is.na(PHASE) ~ "Demand",
#       TRUE ~ PHASE
#     )
#   ) %>%
#   filter(MONTH_WORKTIMESHEET >= floor_date(ymd(Sys.Date()) - years(2), unit = "month") &
#            MONTH_WORKTIMESHEET < floor_date(ymd(Sys.Date()), unit = "month")) %>%
#   group_by(MONTH_WORKTIMESHEET, FTE_BREAKDOWN, USERORG_WORKTIMESHEET) %>%
#   summarize(
#     HOURS_WORKTIMESHEET = sum(HOURS_WORKTIMESHEET),
#     TICKET_NUM = n()
#   ) %>%
#   ungroup() %>%
#   left_join(t_mnap, by = c("MONTH_WORKTIMESHEET" = "IDOSZAK")) %>%
#   mutate(
#     FTE = round(HOURS_WORKTIMESHEET / 7 / MNAP, 2),
#     FTE_NORM = round(FTE / TICKET_NUM, 4)
#   )
# 
# write.csv(t_fte_phases_team, here::here("Data", "t_fte_phases_team.csv"), row.names = FALSE)
# 
# 
# 
# 
# # Leader Board Throughput Open ------------------------------------------
# message("Start Leader Board Throughput Closed aggregation for tickets")
# t_lb_tp_open <- t_backlog_tr %>% 
#   filter(is.na(CLOSED)) %>% 
#   filter(!is.na(LAST_EVENT)) %>% 
#   select(CASE, ISSUE_TITLE, CREATED, TICKET, LAST_EVENT, LAST_EVENT_DATE, APPGROUP) %>% 
#   mutate(DAYS_OPEN = difftime(Sys.Date(), CREATED, units="days")) %>% 
#   group_by(TICKET) %>% 
#   top_n(10, row_number(DAYS_OPEN)) %>% 
#   ungroup() %>% 
#   mutate(DAYS_OPEN = round(DAYS_OPEN, 0)) %>% 
#   arrange(TICKET, desc(DAYS_OPEN)) %>% 
#   select(TICKET, CASE, ISSUE_TITLE, CREATED, TEAM = APPGROUP, DAYS_OPEN, LAST_EVENT, LAST_EVENT_DATE)
# 
# write.csv(t_lb_tp_open, here::here("Data", "t_lb_tp_open.csv"), row.names = FALSE)
# 
# 
# 
# # Leader Board FTE  ------------------------------------------
# message("Start Leader Board FTE aggregation for tickets")
# t_lb_fte_open <- t_fte_tr %>% 
#   filter(is.na(CLOSED)) %>% 
#   group_by(TICKET, CASE, ISSUE_TITLE, CREATED, TEAM = APPGROUP) %>% 
#   summarize(TOTAL_HOURS = sum(HOURS_WORKTIMESHEET)) %>% 
#   ungroup() %>%
#   mutate(MONTHS_OPEN = as.numeric(difftime(Sys.Date(), CREATED, units= "days") / 30),
#          FTE_PER_MONTH = round(TOTAL_HOURS/MONTHS_OPEN/7/21, 2)) %>% 
#   group_by(TICKET) %>% 
#   top_n(10, row_number(TOTAL_HOURS)) %>% 
#   ungroup() %>% 
#   mutate(TOTAL_HOURS = round(TOTAL_HOURS, 0)) %>% 
#   arrange(TICKET, desc(TOTAL_HOURS)) %>% 
#   select(-MONTHS_OPEN)
# 
# write.csv(t_lb_fte_open, here::here("Data", "t_lb_fte_open.csv"), row.names = FALSE)
# 
# 
# 
# 
# # Conformance Analysis Issue List -----------------------------------------
# message("Start Conformance Analysis issue list")
# t_conf <- t_backlog_tr %>%
#   filter(!is.na(CLOSED) & TICKET %in% c("Development", "Development Small") & CLASS_SHORT != "RFC") %>%
#   select(CASE, ISSUE_TITLE, APPLICATION, CREATED, CLOSED, TICKET, CLASS_SHORT, DISTINCT_STEPS, ADMIN_STEP, APPGROUP) %>%
#   tidyr::replace_na(list(ADMIN_STEP = "N")) %>%
#   mutate(STEP_NUM_OK = case_when(
#     TICKET == "Development" & DISTINCT_STEPS < 30 ~ "N",
#     TICKET == "Development Small" & CLASS_SHORT == "DEV" & DISTINCT_STEPS < 25 ~ "N",
#     TICKET == "Development Small" & CLASS_SHORT == "SDEV" & DISTINCT_STEPS < 17 ~ "N",
#     TRUE ~ "I"
#   )) %>%
#   mutate(CONFORM = case_when(
#     APPLICATION == "ISD" & STEP_NUM_OK == "I" ~ "CONFORM",
#     STEP_NUM_OK == "N" | ADMIN_STEP == "I" ~ "DEVIANT",
#     TRUE ~ "CONFORM"
#   )) %>%
#   arrange(TICKET, CREATED) %>%
#   select(TICKET, CASE, ISSUE_TITLE, CREATED, CLOSED, STEPS = DISTINCT_STEPS, ADMIN_STEP, CONFORM)
# 
# write.csv(t_conf, here::here("Data", "t_conf.csv"), row.names = FALSE)
# 
# 
# 
# # Conformance Analysis Aggregation ----------------------------------------
# message("Start Conformance Analysis aggregation")
# t_conf_agg <- t_conf %>%
#   mutate(CREATED_MONTH = as.Date(floor_date(CREATED, unit = "month"))) %>%
#   group_by(CREATED_MONTH, TICKET, CONFORM) %>%
#   summarize(COUNT = n()) %>%
#   ungroup() %>% 
#   # Need to use spread to fill 0 for missing months to make cumulative time-series complete
#   tidyr::spread(CONFORM, COUNT, fill = 0) %>% 
#   # Need to gather to be able to input to ggplot geom_bar(aes(fill=))
#   tidyr::gather(key = CONFORM, value = COUNT, -TICKET, -CREATED_MONTH) %>%
#   arrange(TICKET, CREATED_MONTH) %>%
#   group_by(TICKET) %>% 
#   mutate(CUMULATIVE_COUNT = cumsum(COUNT)) %>%
#   ungroup()
#   
# write.csv(t_conf_agg, here::here("Data", "t_conf_agg.csv"), row.names = FALSE)
#   
# 
