library(magrittr)

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
    return(data.frame("COUNT"=1))
  } else {
    return(data.frame("COUNT"=0))
  }
}



get_backlog <- function(df, cutpoints, ...) {
  # Fuction to count number of units in backlog for given cutpoints
  # using purrr with multiple groups
  # 
  # Args
  #   df: Data Frame of cases with START and END dates plus grouping variables
  #   cutpoints: Data Frame of cutpoints to compute backlog for
  #   group_var: Variable to group by
  #   
  # Returns
  #   Data Frame: cutpoints extended with col BACKLOG holding
  #   backlog size for each cutpoint
  
  # Create grid of intervals and dates combinations to check
  group_vars <- rlang::enquos(...)
  
  backlog <- base::merge(df, cutpoints) %T>% {print('Finish merge')} %>% 
    select(START, END, CUTPOINT, !!!group_vars) %T>% {print('Finish select')} %>% 
    # Map helper for every combination
    cbind(purrr::pmap_dfr(., ~check_date(..1, ..2, ..3))) %T>% {print('Finish cbind')} %>% 
    # Save computation results to return obj
    group_by(CUTPOINT, !!!group_vars) %T>% {print('Finish groupby')} %>% 
    summarize(COUNT = sum(COUNT)) %>% 
    ungroup()
  
  return(backlog)
}