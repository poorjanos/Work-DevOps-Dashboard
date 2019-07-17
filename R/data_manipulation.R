library(dplyr)
library(purrr)


# Generate random sample --------------------------------------------------
set.seed(42)
sample_size = 10
t_cases <- tibble(START = sample(seq(as.Date('2019/01/01'),
                                     Sys.Date(), by="day"), sample_size)) %>%
  # Add random noise to get end dates
  mutate(DIFF = sample(50, size = nrow(.), replace = TRUE),
         END = START + DIFF) %>% 
  # Set end dates greater than Sys.Date to NA
  mutate(END = replace(END, END >= Sys.Date(), NA)) %>% 
  select(START, END)


# Genarate cutpoints ------------------------------------------------------
# Full range of days in sample up until Sys.Date
t_cp_days <-  tibble(CUTPOINTS = seq(min(t_cases$START), Sys.Date(), by = 1))
# First days of months in sample
t_cp_months <- tibble(
  CUTPOINTS = unique(lubridate::floor_date(t_cp_days$CUTPOINTS, unit = "month"))
  )


# For loop solution -------------------------------------------------------
get_stock_loop <- function(df, cutpoints) {
  # Fuction to count number of cases in stock for given cutpoints using for loops
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
months <- get_stock_loop(t_cases, t_cp_months)
days <- get_stock_loop(t_cases, t_cp_days)



# purrr solution ----------------------------------------------------------
# Define helper func
check_date <- function(start_date, end_date, check_date) {
  # Fuction to check a date is part of an interval
  # 
  # Args
  #   start_date: Interval open date
  #   end_date: Interval close date
  #   check_date: Date to check
  #   
  # Returns
  #   Data Frame: single cell df with a flag
  #   
  if (check_date >= start_date & (is.na(end_date) | check_date <= end_date)) {
    return(data.frame("STOCK"=1))
  } else {
    return(data.frame("STOCK"=0))
  }
}



get_stock_purrr <- function(df, cutpoints) {
  # Fuction to count number of cases in stock for given cutpoints using purrr
  # 
  # Args
  #   df: Data Frame of cases with START and END dates
  #   cutpoints: Data Frame of cutpoints to compute stock for
  #   
  # Returns
  #   Data Frame: cutpoints extended with col STOCK holding results of
  #   stock computation for each cutpoint

  # Create grid of intervals and dates combinations to check
  stock <- merge(df, cutpoints) %>% 
    # Map helper for every combination
    cbind(purrr::pmap_dfr(., ~check_date(..1, ..2, ..3))) %>% 
    # Save computation results to return obj
    group_by(CUTPOINTS) %>% 
    summarize(STOCK = sum(STOCK))
  
  return(stock)
}

# Test get_stock_purrr
get_stock_purrr(t_cases, t_cp_months)
get_stock_purrr(t_cases, t_cp_days)






# Grouped purrr solution --------------------------------------------------
GROUPVAR1 = sample(c('a', 'b', 'c'), sample_size, replace = TRUE)
GROUPVAR2 = sample(c('x', 'y', 'z'), sample_size, replace = TRUE)

t_cases_groups <- cbind(t_cases, GROUPVAR1, GROUPVAR2)


# Grouped version of purrr
get_stock_purrr_grouped <- function(df, cutpoints, group_var) {
  # Fuction to count number of cases in stock for given cutpoints using purrr with single group
  # 
  # Args
  #   df: Data Frame of cases with START and END dates plus grouping var(s)
  #   cutpoints: Data Frame of cutpoints to compute stock for
  #   group_var: Variable to group by
  #   
  # Returns
  #   Data Frame: cutpoints extended with col STOCK holding results of
  #   stock computation for each cutpoint
  
  # Create grid of intervals and dates combinations to check
  stock <- merge(df[c("START", "END", deparse(substitute(group_var)))], cutpoints) %>% 
    # Map helper for every combination
    cbind(purrr::pmap_dfr(., ~check_date(..1, ..2, ..4))) %>% 
    # Save computation results to return obj
    group_by(CUTPOINTS, !!rlang::enquo(group_var)) %>% 
    summarize(STOCK = sum(STOCK))

  return(stock)
}

# Test get_stock_purrr_grouped
get_stock_purrr_grouped(t_cases_groups, t_cp_months, GROUPVAR1)





# Grouped version of purrr
get_stock_purrr_grouped_multiple <- function(df, cutpoints, ...) {
  # Fuction to count number of cases in stock for given cutpoints using purrr with multiple groups
  # 
  # Args
  #   df: Data Frame of cases with START and END dates plus grouping var(s)
  #   cutpoints: Data Frame of cutpoints to compute stock for
  #   group_var: Variable to group by
  #   
  # Returns
  #   Data Frame: cutpoints extended with col STOCK holding results of
  #   stock computation for each cutpoint
  
  # Create grid of intervals and dates combinations to check
  print(substitute(...))
  stock <- merge(df[c("START", "END", deparse(substitute(...)))], cutpoints) #%>% 
    # Map helper for every combination
    #cbind(purrr::pmap_dfr(., ~check_date(..1, ..2, ..4))) %>% 
    # Save computation results to return obj
    #group_by(CUTPOINTS, !!rlang::enquo(group_var)) %>% 
    #summarize(STOCK = sum(STOCK))
  
  return(stock)
}

# Test get_stock_purrr_grouped
get_stock_purrr_grouped_multiple(t_cases_groups, t_cp_months, c(GROUPVAR1, GROUPVAR2))



# Timing












df <- rbind(cbind(group = 'a', df),cbind(group = 'b', df)) %>% as_tibble


df %>% 
  group_by(.,group) %>% 
  do(data.frame(table(Reduce(c, Map(seq, .$START, .$END, by = 1)))))


