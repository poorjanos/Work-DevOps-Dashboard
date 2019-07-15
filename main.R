library(here)
library(config)
library(dplyr)
library(lubridate)



# Data Extraction ---------------------------------------------------------

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
query_stock <- readQuery(here::here("SQL", "get_stock.sql"))
t_stock <- dbGetQuery(jdbcConnection, query_stock)

# Close db connection: kontakt
dbDisconnect(jdbcConnection)



# Transformations ---------------------------------------------------------

t_stock <- t_stock %>% mutate(
  CREATED = ymd_hms(CREATED),
  CLOSED = ymd_hms(CLOSED),
  APPGROUP = case_when(
    stringr::str_detect(APPLICATION_GROUP_CONCAT, "/") ~ "Z_Közös",
    TRUE ~ APPLICATION_GROUP_CONCAT
  ),
  APPSINGLE = case_when(
    stringr::str_detect(APPLICATION, ";") ~ "Multiple",
    TRUE ~ "Single"
  )
)

