# Define helper funcs and create sample -----------------------------------
# Define date check function
check_date <- function(start_date, end_date, check_date) {
  if (check_date >= start_date & (is.na(end_date) | check_date <= end_date)) {
    return(data.frame("IN_STOCK"=1))
  } else {
    return(data.frame("IN_STOCK"=0))
  }
}

# Test date check function
s <-  as.Date('2019-01-10')
e <-  NA
c <- as.Date('2019-05-10')
check_date(s,e,c)

# Create sammple for testing
t_stock_head = head(t_stock, 10)

seq(as.Date(min(t_stock_head$CREATED)), Sys.Date(), by = 1)

# Purrr solution ----------------------------------------------------------
t_stock_head %>%
mutate(id = as.character(row_number())) %>% 
left_join(purrr::pmap_dfr(list(t_stock_head$CREATED, t_stock_head$CLOSED), check_date2, as.POSIXct('2018-09-01'), .id = "id"), by = "id") %>% 
summarize(sum(IN_STOCK))



# Map-Reduce solution -----------------------------------------------------
df <-  data_frame(
  START = as.Date(c("2014-01-01", "2014-01-02","2014-01-03","2014-01-03")),
  END   = as.Date(c("2014-01-04", "2014-01-03","2014-01-03","2014-01-04"))
)


df <- rbind(cbind(group = 'a', df),cbind(group = 'b', df)) %>% as_tibble


df %>% 
  group_by(.,group) %>% 
  do(data.frame(table(Reduce(c, Map(seq, .$START, .$END, by = 1)))))


