#' Scrape Bath Rugby match dates, kick-off times and results
#'
#' Web scraping function to gather dates and times of Bath Rugby matches, and
#'  whether or not Bath won, from the
#'  \href{http://www.bathrugby.com/fixtures-results/results-tables/results-match-reports/}{Bath Rugby website}.\cr\cr
#'  \emph{Note: This function's code is heavily commented so that if you want
#'   to, you can use it as a tutorial/guide for writing similar functions of
#'   your own! You can view the commented code on the GitHub repo
#'   \href{https://github.com/owenjonesuob/BANEScarparking/blob/master/R/web_scraping.R}{here}}.
#'
#' @param x A vector of years of seasons to retrieve records from.
#' @return A data frame of kick-off date-times and match outcomes.
#' @examples
#' # Return matches from 2014/15, 2015/16 seasons
#' seasons <- c(2015, 2016)
#' rugby <- get_rugby(seasons)
#'
#' @export

get_rugby <- function(x) {

    # Set up data frame, to be added to shortly
    rugby <- data.frame(GMT = character(0), HomeWin = logical(0))

    # For each season:
    for (i in 1:length(x)) {

        # Put together the link to the webpage for the season's fixtures
        address <- paste0("http://www.bathrugby.com/fixtures-results/",
                          "results-tables/results-match-reports/",
                          "?seasonEnding=", x[i])


        # "Parse" page so we can work with it in R
        parsedpage <- RCurl::getURL(address) %>%
            XML::htmlParse()

        # Scrape required information from page (first, home match dates):
        # xpathSApply returns a vector (simplified from a list, hence SApply
        # rather than Apply) of HTML "nodes" satisfying certain conditions...
        dates <- XML::xpathSApply(parsedpage,
                                  # First, (visually) find the information we're
                                  # interested in on the webpage (just using a
                                  # browser). Then use the developer console
                                  # (launch with F12, or Cmd+Option+I on Mac) to
                                  # inspect the HTML.
                                  #
                                  # Now to grab the bits of HTML we are
                                  # interested in. Define conditions using XPath
                                  # query language:
                                  # * //dd finds all nodes of type "dd"
                                  # * [@class='...'] takes the subset of nodes
                                  #   with "class" attribute "..."
                                  # * / finds all "child" nodes of currently
                                  # selected nodes
                                  paste0("//dd[@class='fixture homeFixture']",
                                         "/span[@class='fixtureDate']"),
                                  # We want the value (in this case, the string)
                                  # contained between the HTML tags of these
                                  # nodes (the 'contents' of the node): the XML
                                  # function xmlValue does this for us!
                                  XML::xmlValue) %>%
            # We currently have a string such as " 6 Sep 2014" or "13 Sep 2014",
            # but this would be more useful as a date-time!
            # See documentation of strptime for % abbreviations to use in the
            # "format" string. In this case we're telling the as.POSIXct
            # function that:
            #   '%n': there might be a space, or a few spaces
            #   '%e': day number, as a decimal
            #   ' ' : there's definitely a space here
            #   '%b': abbreviated month name
            #   ' ' : another space
            #   '%Y': 4-digit year
        as.POSIXct(format = "%n%e %b %Y", tz = "UTC") %>%
            # Reverse order of elements (to restore chronological order)
            rev()

        # Now, kick-off times:
        KO <- XML::xpathSApply(parsedpage,
                               paste0("//dd[@class='fixture homeFixture']",
                                      "/span[@class='fixtureTime']"),
                               XML::xmlValue) %>%
            # Values are currently strings of form "Kick Off 00:00"
            # Take 10th character onwards:
            substring(10) %>%
            # Convert to hour-minute time
            lubridate::hm() %>%
            rev()

        # Combine date and time (just use +, R handles this for us!)
        GMT <- dates + KO

        # Results of the matches: did Bath win? (Maybe people hang around in
        # town for longer afterwards if so.)
        HomeWin <- XML::xpathSApply(parsedpage,
                                    paste0("//dd[@class='fixture homeFixture']",
                                           "/span[@class='fixtureResult']"),
                                    XML::xmlValue) %>%
            # Values are "Bath won ..." or "Bath lost ...".
            # grepl returns TRUE if element contains a string, FALSE if it
            # doesn't Note: The "." is the pipe's "placeholder" argument: by
            # default, %>% passes on the previous step's result as the FIRST
            # parameter. Here, we need to pass it as the second argument, so
            # have to use "." to represent it.
            grepl("won", .) %>%
            rev()

        # Stick the GMT and HomeWin vectors together as columns of a data frame
        toAdd <- data.frame(GMT, HomeWin)

        # Attach this dataframe to the existing data frame of all matches
        rugby <- rbind(rugby, toAdd)
    }

    # Return the complete data frame
    rugby
}


#' Scrape the number of advertised events in Bath for each day
#'
#' Web scraping function to retrieve the number of events advertised at
#'  \url{http://www.bath.co.uk/events} for each day in a specified range of
#'  months.\cr\cr
#'  \emph{Note: Have a look at this package's GitHub repo - in particular,
#'   \href{https://github.com/owenjonesuob/BANEScarparking/blob/master/R/web_scraping.R}{here}
#'   - to see the code for this function, along with comments which
#'   explain the process followed. See \code{\link{get_rugby}} for a similar
#'   function with more detailed commentary!}
#'
#' @param from A date or date-time object, or YYYY-MM-DD string: the first day
#'  from which to get an event count.
#' @param to A date or date-time object, or YYYY-MM-DD string: the last day
#'  from which to get an event count.
#' @return A data frame of daily event counts for each day in the specified
#'  range.
#' @examples
#' # Return daily event counts from 01 Oct 2014 to 17 Jul 2015
#' events <- get_events("2014-10-01", "2015-07-17")
#'
#' # Return daily event counts for all months in date range of parking records
#' raw_data <- get_all_crude()
#' DF <- refine(raw_data)
#'
#' events <- get_events(min(DF$LastUpdate), max(DF$LastUpdate))
#' @export

get_events <- function(from, to) {

    # Get all year-month combinations in specified range
    year_month <- seq(as.Date(from), as.Date(to), by = "months") %>%
        substr(., 0, nchar(.)+2)

    # Create web addresses for past events pages
    addresses <- paste0("http://www.bath.co.uk/events/", year_month)

    # Initialize event-count vector
    event_count <- vector("list", length(addresses))
    names(event_count) <- year_month

    # For each year-month:
    for (i in 1:length(addresses)) {

        # "Parse" page so we can work with it in R
        parsedpage <- RCurl::getURL(addresses[i]) %>%
            XML::htmlParse()

        # Find all days from current month
        day_events <- XML::xpathApply(parsedpage,
                                      paste0("//td[contains(@class, ",
                                             "'tribe-events-thismonth')]"))

        # Set up a vector to store number of events from each day in a month
        daily_event_count <- vector("integer", length(day_events))

        # For each day:
        for (j in 1:length(day_events)) {

            # Look for a "view more" node
            view_more <- XML::xpathSApply(day_events[[j]],
                                         "div[@class='tribe-events-viewmore']",
                                         XML::xmlValue)

            # If such a node exists...
            if (length(view_more) > 0) {
                # ... it contains a string of the form "View all x events", so
                # we isolate x by using gsub to replace all non-digit characters
                # (the caret ^ means "all except") with "" (nothing!), and then
                # convert the string "x" to a number
                daily_event_count[j] <- view_more %>%
                    gsub("[^0-9]", "", .) %>%
                    as.numeric()
            } else {
                # If there is no "view more" node, then we simply count the
                # number of 'div's: there is one more div than events, because
                # the day number (which isn't an event!) is also found in a div
                daily_event_count[j] <- XML::xpathApply(day_events[[j]],
                                                        "div") %>%
                    length() - 1
            }
        }

        # Add this list to our list of year-month event counts
        event_count[[i]] <- daily_event_count
    }

    # Trim the last month... (events only up to "to" date)
    lec <- length(event_count)
    event_count[[lec]] <- head(event_count[[lec]], lubridate::day(to))

    # Then the first month... (events only from "from" date)
    event_count[[1]] <- tail(event_count[[1]], -lubridate::day(from) + 1)


    # Get all dates in the months we are looking at
    all_dates <- seq(as.Date(from), as.Date(to), by = "days")

    # Make a data frame with each date and the number of events that day:
    # "unlist" does exactly as it says on the tin, it just stretches a list out
    # into a long vector
    events <- data.frame(Date = all_dates, count = unlist(event_count))

    # Get rid of unnecessary numeric row names
    rownames(events) <- NULL

    # Return the complete data frame!
    events
}


