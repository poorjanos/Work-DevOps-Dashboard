library(dplyr)


# Generate random sample --------------------------------------------------
t_cases <- tibble(START = sample(seq(as.Date('2019/01/01'),
                                     Sys.Date(), by="day"), 10)) %>%
  # Add random noise to get end dates
  mutate(DIFF = sample(50, size = nrow(.), replace = TRUE),
         END = START + DIFF) %>% 
  # Set end dates greater than Sys.Date to NA
  mutate(END = replace(END, END >= Sys.Date(), NA)) %>% 
  select(START, END)


# Genarate cutpoints ------------------------------------------------------
# Full range of days in sample up until Sys.Date
t_cp_days <-  tibble(CUTPOINTS = seq(min(df$START), Sys.Date(), by = 1))
# First days of months in sample
t_cp_months <- tibble(
  CUTPOINTS = unique(lubridate::floor_date(cp_days$CUTPOINTS, unit = "month"))
  )


# For loop solution -------------------------------------------------------
get_stock_loop <- function(df, cutpoints) {
  # Fuction to count number of cases in stock for given cutpoints
  # 
  # Args
  #   df: Data Frame of cases with START and END dates
  #   cutpoints: Data Frame of cutpoints to compute stock for
  #   
  # Returns
  #   Data Frame: cutpoints extended with col STOCK holding results of
  #   stock computation for each cutpoint
  
  # Define return obj
  stock <- cutpoints
  stock$STOCK <- 0

  # Loop on cutpoints
  for (cutpoint in 1:nrow(cutpoints)) {
    res <- 0
    # Loop on cases
    for (case in 1:nrow(df)) {
      # Test for stock membership
      if (cutpoints[[cutpoint, "CUTPOINTS"]] >= df[[case, "START"]] &
          (is.na(df[[case, "END"]]) | cutpoints[[cutpoint, "CUTPOINTS"]] <= df[[case, "END"]])){
        res <- res + 1
      }
    }
    # Save computation results to return obj
    stock[cutpoint, "STOCK"] <- res
  }
  return(stock)
}


# Test get_stock_loop
months <- get_stock_loop(df, cp_months)
days <- get_stock_loop(df, cp_days)



# purrr solution ----------------------------------------------------------
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
left_join(purrr::pmap_dfr(list(t_stock_head$CREATED, t_stock_head$CLOSED), check_date, as.POSIXct('2018-09-01'), .id = "id"), by = "id") %>% 
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


