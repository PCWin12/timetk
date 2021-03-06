#' Make future time series from existing
#'
#' @param idx A vector of dates
#' @param n_future Number of future observations
#' @param inspect_weekdays Uses a logistic regression algorithm to inspect
#'  whether certain weekdays (e.g. weekends) should be excluded from the future dates.
#'  Default is `FALSE`.
#' @param inspect_months Uses a logistic regression algorithm to inspect
#'  whether certain days of months (e.g. last two weeks of year or seasonal days)
#'  should be excluded from the future dates.
#'  Default is `FALSE`.
#' @param skip_values A vector of same class as `idx` of timeseries
#'  values to skip.
#' @param insert_values A vector of same class as `idx` of timeseries
#'  values to insert.
#'
#' @details
#'
#' __Future Sequences__
#'
#' `tk_make_future_timeseries` returns a time series based
#' on the input index frequency and attributes.
#'
#' The argument `n_future` determines how many future index observations to compute.
#'
#' The `inspect_weekdays` and `inspect_months` arguments apply to "daily" (scale = "day") data
#' (refer to `tk_get_timeseries_summary()` to get the index scale).
#' The `inspect_weekdays` argument is useful in determining missing days of the week
#' that occur on a weekly frequency such as every week, every other week, and so on.
#' It's recommended to have at least 60 days to use this option.
#' The `inspect_months` argument is useful in determining missing days of the month, quarter
#' or year; however, the algorithm can inadvertently select incorrect dates if the pattern
#' is erratic.
#'
#' For example, some holidays do not occur on the same day of each month, and
#' as a result the incorrect day may be selected in certain years.
#' It's recommended to always review the date results to ensure the future days match
#' the user's expectations. It's recommended to have at least two years of days to use
#' this option.
#'
#' The `skip_values` and `insert_values` arguments can be used to remove and add
#' values into the series of future times. The values must be the same format as the `idx` class.
#' The `skip_values` argument useful for passing holidays or special index values that should
#' be excluded from the future time series.
#' The `insert_values` argument is useful for adding values back that the algorithm may have
#' excluded.
#'
#' __Holiday Sequences__
#'
#'
#'
#' @return A vector containing future index of the same class as the incoming index `idx`
#'
#' @seealso
#' - Working with Holidays: [tk_make_holiday_sequence()]
#' - Working with Timestamp Index: [tk_index()], [tk_get_timeseries_summary()], [tk_get_timeseries_signature()]
#'
#' @examples
#' library(dplyr)
#' library(tidyquant)
#' library(timetk)
#'
#' # Basic example
#' idx <- c("2016-01-01 00:00:00",
#'          "2016-01-01 00:00:03",
#'          "2016-01-01 00:00:06") %>%
#'     ymd_hms()
#' # Make next three dates in series
#' idx %>%
#'     tk_make_future_timeseries(n_future = 3)
#'
#'
#' # Create index of days that FB stock will be traded in 2017 based on 2016 + holidays
#' FB_tbl <- FANG %>% filter(symbol == "FB")
#'
#' holidays <- tk_make_holiday_sequence(
#'     start_date = "2017-01-01",
#'     end_date   = "2017-12-31",
#'     calendar   = "NYSE")
#'
#' # Remove holidays with skip_values, and remove weekends with inspect_weekdays = TRUE
#' FB_tbl %>%
#'     tk_index() %>%
#'     tk_make_future_timeseries(n_future         = 366,
#'                               inspect_weekdays = TRUE,
#'                               skip_values      = holidays)
#'
#' # Works with regularized indexes as well
#' c(2016.00, 2016.25, 2016.50, 2016.75) %>%
#'     tk_make_future_timeseries(n_future = 4)
#'
#' # Works with zoo yearmon and yearqtr too
#' c("2016 Q1", "2016 Q2", "2016 Q3", "2016 Q4") %>%
#'     as.yearqtr() %>%
#'     tk_make_future_timeseries(n_future = 4)
#'
#'
#' @name tk_make_timeseries
NULL

# FUTURE TIMESERIES ----

#' @export
#' @rdname tk_make_timeseries
tk_make_future_timeseries <- function(idx, n_future, inspect_weekdays = FALSE, inspect_months = FALSE, skip_values = NULL, insert_values = NULL) {
    UseMethod("tk_make_future_timeseries", idx)
}

#' @export
tk_make_future_timeseries.POSIXt <- function(idx, n_future, inspect_weekdays = FALSE, inspect_months = FALSE, skip_values = NULL, insert_values = NULL) {
    return(make_sequential_timeseries_irregular_freq(idx = idx, n_future = n_future, skip_values = skip_values, insert_values = insert_values))
}

#' @export
tk_make_future_timeseries.Date <- function(idx, n_future, inspect_weekdays = FALSE, inspect_months = FALSE, skip_values = NULL, insert_values = NULL) {

    if (missing(n_future)) {
        warning("Argument `n_future` is missing with no default")
        return(NA)
    }

    # Daily Periodicity + Inspect Weekdays
    idx_summary <- tk_get_timeseries_summary(idx)

    if (idx_summary$scale == "day" && (inspect_weekdays || inspect_months)) {

        # Daily scale with weekday and/or month inspection
        tryCatch({

            return(predict_future_timeseries_daily(idx = idx, n_future = n_future, inspect_weekdays = inspect_weekdays, inspect_months = inspect_months, skip_values = skip_values, insert_values = insert_values))

        }, error = function(e) {

            warning(paste0("Could not perform `glm()`: ", e, "\nMaking sequential timeseries."))
            return(make_sequential_timeseries_irregular_freq(idx = idx, n_future = n_future, skip_values = skip_values, insert_values = insert_values))

        })

    } else if (idx_summary$scale == "day") {

        # Daily scale without weekday inspection
        return(make_sequential_timeseries_irregular_freq(idx = idx, n_future = n_future, skip_values = skip_values, insert_values = insert_values))

    } else if (idx_summary$scale == "week") {

        # Weekly scale
        return(make_sequential_timeseries_irregular_freq(idx = idx, n_future = n_future, skip_values = skip_values, insert_values = insert_values))

    } else if (idx_summary$scale == "month") {

        # Monthly scale - Switch to yearmon and then back to date
        if (!is.null(skip_values)) skip_values <- zoo::as.yearmon(skip_values)
        if (!is.null(insert_values)) insert_values <- zoo::as.yearmon(insert_values)
        ret  <- zoo::as.yearmon(idx) %>%
            tk_make_future_timeseries(n_future = n_future, skip_values = skip_values, insert_values = insert_values) %>%
            lubridate::as_date()
        return(ret)

    } else if (idx_summary$scale == "quarter") {

        # Quarterly scale - Switch to yearqtr and then back to date
        if (!is.null(skip_values)) skip_values <- zoo::as.yearqtr(skip_values)
        if (!is.null(insert_values)) insert_values <- zoo::as.yearqtr(insert_values)
        ret  <- zoo::as.yearqtr(idx) %>%
            tk_make_future_timeseries(n_future = n_future, skip_values = skip_values, insert_values = insert_values) %>%
            lubridate::as_date()
        return(ret)

    } else {

        # Yearly scale - Use yearmon and rely on frequency to dictate yearly scale
        if (!is.null(skip_values)) skip_values <- zoo::as.yearmon(skip_values)
        if (!is.null(insert_values)) insert_values <- zoo::as.yearmon(insert_values)
        ret  <- zoo::as.yearmon(idx) %>%
            tk_make_future_timeseries(n_future = n_future, skip_values = skip_values, insert_values) %>%
            lubridate::as_date()
        return(ret)
    }

}

#' @export
tk_make_future_timeseries.yearmon <- function(idx, n_future, inspect_weekdays = FALSE, inspect_months = FALSE, skip_values = NULL, insert_values = NULL) {
    return(make_sequential_timeseries_regular_freq(idx = idx, n_future = n_future, skip_values = skip_values, insert_values = insert_values))
}

#' @export
tk_make_future_timeseries.yearqtr <- function(idx, n_future, inspect_weekdays = FALSE, inspect_months = FALSE, skip_values = NULL, insert_values = NULL) {
    return(make_sequential_timeseries_regular_freq(idx = idx, n_future = n_future, skip_values = skip_values, insert_values = insert_values))
}

#' @export
tk_make_future_timeseries.numeric <- function(idx, n_future, inspect_weekdays = FALSE, inspect_months = FALSE, skip_values = NULL, insert_values = NULL) {
    return(make_sequential_timeseries_regular_freq(idx = idx, n_future = n_future, skip_values = skip_values, insert_values = insert_values))
}


# UTILITIY FUNCTIONS -----

predict_future_timeseries_daily <- function(idx, n_future, inspect_weekdays, inspect_months, skip_values, insert_values) {

    # Validation
    if (!is.null(skip_values)) {
        if (class(skip_values)[[1]] != class(idx)[[1]]) {
            warning("Class `skip_values` does not match class `idx`.", call. = FALSE)
            return(NA)
        }
    }

    if (!is.null(insert_values)) {
        if (class(insert_values)[[1]] != class(idx)[[1]]) {
            warning("Class `insert_values` does not match class `idx`.", call. = FALSE)
            return(NA)
        }
    }

    if ((length(idx) < 60) && inspect_weekdays) warning("Less than 60 observations could result in incorrectly predicted weekday frequency due to small sample size.")
    if ((length(idx) < 400) && inspect_months) warning("Less than 400 observations could result in incorrectly predicted month frequency due to small sample size.")

    # Get index attributes
    idx_signature         <- tk_get_timeseries_signature(idx)
    idx_summary           <- tk_get_timeseries_summary(idx)

    # Find start and end
    start <- min(idx)
    end   <- max(idx)

    # Format data frame
    suppressMessages({
        train <- tibble::tibble(
            index = idx,
            y     = rep(1, length(idx))) %>%
            padr::pad(start_val = start, end_val = end) %>%
            padr::fill_by_value(y, value = 0) %>%
            tk_augment_timeseries_signature(.date_var = index)
    })


    # fit model based on components
    f <- make_daily_prediction_formula(train, inspect_weekdays, inspect_months)
    fit <- suppressWarnings(
        stats::glm(f, family = stats::binomial(link = 'logit'), data = train)
    )

    # Create new data
    last_numeric_date <- idx_summary$end %>%
        lubridate::as_datetime() %>%
        as.numeric()
    frequency         <- idx_summary$diff.median
    next_numeric_date <- last_numeric_date + frequency
    numeric_sequence  <- seq(from = next_numeric_date, by = frequency, length.out = n_future)

    date_sequence <- lubridate::as_datetime(numeric_sequence) %>%
        lubridate::as_date()

    # Create new_data data frame with future obs timeseries signature
    new_data <- date_sequence %>%
        tk_get_timeseries_signature()

    # Predict
    fitted_results <- suppressWarnings(
        stats::predict(fit, newdata = new_data, type = 'response')
        )
    fitted_results <- ifelse(fitted_results > 0.5, 1, 0)

    # Filter on fitted.results
    predictions <- tibble::tibble(
        index = date_sequence,
        yhat  = fitted_results
        )

    predictions <- predictions %>%
        dplyr::filter(yhat == 1)

    # Filter skip_values
    idx_pred <- filter_skip_values(predictions$index, skip_values, n_future)
    idx_pred <- add_insert_values(idx_pred, insert_values)

    # Return date sequence
    return(idx_pred)
}

make_sequential_timeseries_irregular_freq <- function(idx, n_future, skip_values, insert_values) {

    # Validation
    if (!is.null(skip_values)) {
        if (class(skip_values)[[1]] != class(idx)[[1]]) {
            warning("Class `skip_values` does not match class `idx`.", call. = FALSE)
            return(NA)
        }
    }

    if (!is.null(insert_values)) {
        if (class(insert_values)[[1]] != class(idx)[[1]]) {
            warning("Class `insert_values` does not match class `idx`.", call. = FALSE)
            return(NA)
        }
    }

    # Get index attributes
    idx_signature         <- tk_get_timeseries_signature(idx)
    idx_summary           <- tk_get_timeseries_summary(idx)

    # Create date sequence based on index.num and median frequency
    last_numeric_date <- dplyr::last(idx_signature$index.num)
    frequency         <- idx_summary$diff.median
    next_numeric_date <- last_numeric_date + frequency
    numeric_sequence  <- seq(from = next_numeric_date, by = frequency, length.out = n_future)

    if (inherits(idx, "Date")) {
        # Date
        date_sequence <- lubridate::as_datetime(numeric_sequence) %>%
            lubridate::as_date()
    } else {
        # Datetime
        date_sequence <- lubridate::as_datetime(numeric_sequence)
        lubridate::tz(date_sequence) <- lubridate::tz(idx)
    }

    # Filter skip_values
    date_sequence <- filter_skip_values(date_sequence, skip_values, n_future)
    date_sequence <- add_insert_values(date_sequence, insert_values)

    # Return date sequence
    return(date_sequence)
}


make_sequential_timeseries_regular_freq <- function(idx, n_future, skip_values, insert_values) {

    # Validation
    if (!is.null(skip_values)) {
        if (class(skip_values)[[1]] != class(idx)[[1]]) {
            warning("Class `skip_values` does not match class `idx`.", call. = FALSE)
            return(NA)
        }
    }

    if (!is.null(insert_values)) {
        if (class(insert_values)[[1]] != class(idx)[[1]]) {
            warning("Class `insert_values` does not match class `idx`.", call. = FALSE)
            return(NA)
        }
    }

    # Get index attributes
    idx_numeric   <- as.numeric(idx)
    idx_diff      <- diff(idx)
    median_diff   <- stats::median(idx_diff)

    # Create date sequence based on index.num and median frequency
    last_numeric_date <- dplyr::last(idx_numeric)
    frequency         <- median_diff
    next_numeric_date <- last_numeric_date + frequency
    numeric_sequence  <- seq(from = next_numeric_date, by = frequency, length.out = n_future)

    if (inherits(idx, "yearmon")) {
        # yearmon
        date_sequence <- zoo::as.yearmon(numeric_sequence)
    } else if (inherits(idx, "yearqtr")) {
        # yearqtr
        date_sequence <- zoo::as.yearqtr(numeric_sequence)
    } else {
        # numeric
        date_sequence <- numeric_sequence
    }

    # Filter skip_values
    date_sequence <- filter_skip_values(date_sequence, skip_values, n_future)
    date_sequence <- add_insert_values(date_sequence, insert_values)

    # Return date sequence
    return(date_sequence)
}

filter_skip_values <- function(date_sequence, skip_values, n_future) {
    # Filter skip_values
    if (!is.null(skip_values)) {

        # Remove duplicates
        skip_values <- unique(skip_values)

        # Inspect skip_values
        skips_not_in_seq <- skip_values[!(skip_values %in% date_sequence[1:n_future])]
        if (length(skips_not_in_seq) > 0)
            message(paste0("The following `skip_values` were not in the future date sequence: ", stringr::str_c(skips_not_in_seq, collapse = ", ")))

        # Filter skip_values
        filter_skip_vals <- !(date_sequence %in% skip_values)
        date_sequence <- date_sequence[filter_skip_vals]
    }

    return(date_sequence)
}

add_insert_values <- function(date_sequence, insert_values) {
    # Add insert values

    ret <- date_sequence

    if (!is.null(insert_values)) {

        # Remove duplicates
        insert_values <- unique(insert_values)

        # Inspect insert_values
        adds_in_seq <- insert_values[(insert_values %in% date_sequence)]
        if (length(adds_in_seq) > 0)
            message(paste0("The following `insert_values` were already in the future date sequence: ", stringr::str_c(adds_in_seq, collapse = ", ")))

        # Correct timezone
        if (inherits(date_sequence, "Date")) {

            # Deal with time zones
            numeric_sequence <- date_sequence %>%
                lubridate::as_datetime() %>%
                as.numeric()
            numeric_insert_values <- insert_values %>%
                lubridate::as_datetime() %>%
                as.numeric()

            ret <- c(numeric_sequence, numeric_insert_values[!(numeric_insert_values %in% numeric_sequence)]) %>%
                sort() %>%
                lubridate::as_datetime() %>%
                lubridate::as_date()

        } else if (inherits(date_sequence, "POSIXt")) {

            # Deal with time zones
            numeric_sequence <- as.numeric(date_sequence)
            numeric_insert_values <- as.numeric(insert_values)

            ret <- c(numeric_sequence, numeric_insert_values[!(numeric_insert_values %in% numeric_sequence)]) %>%
                sort() %>%
                lubridate::as_datetime()

            lubridate::tz(ret) <- lubridate::tz(date_sequence)

        } else {

            ret <- c(date_sequence, insert_values[!(insert_values %in% date_sequence)]) %>%
                sort()

        }


    }

    return(ret)
}

make_daily_prediction_formula <- function(ts_signature_tbl_train, inspect_weekdays, inspect_months) {

    nm_list <- list()

    # inspect_weekdays
    if (inspect_weekdays) nm_list <- append(nm_list, list("wday.lbl", "week2", "week3", "week4", "wday.lbl:week2", "wday.lbl:week3", "wday.lbl:week4"))

    # inspect_months
    if (inspect_months) {
        # Need all 12 months and time span to be at least across 2 years
        if (length(unique(ts_signature_tbl_train$month)) == 12 &&
            length(unique(ts_signature_tbl_train$year)) >= 2) {
            nm_list <- append(nm_list, list("week", "month.lbl", "month.lbl:week"))
        } else {
            message("Insufficient timespan / months to perform inspect_month prediction.")
        }
    }

    # Build formula
    params <- stringr::str_c(nm_list, collapse = " + ")
    f <- stats::as.formula(paste0("y ~ ", params))

    return(f)
}

