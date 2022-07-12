# Notes
# Log Item Syntax():
# - [ ] optional_time | description
# time syntax:
# 13:00 = at 13:00
# <13:00 = before 13:00
# >13:00 = after 13:00
# 12:00-13:00 = from 12:00 to 13:00
# 12:00<t<13:00 = somewhen between 12:00 and 13:00
# 12:00<<13:00 = somewhen between 12:00 and 13:00
# each time can be followed by a space and a duration like so:
# 13:00 P2h15m = start at 13:00 and do task for 2h and 15 min
# 12:00<<13:00 P20m = task starts somewhere between 12:00 and 13:00 and needs 20 minutes

# TODO use duration.janet as inspiration to parse durations?

# WARNING heavy work in progress
(defn parse-log-item-time [item-string &opt tdy]
  (default tdy (date/today-local))
  (cond
    (peg/match ~(* :d :d ":" :d :d) item-string)
      (let [components (string/split ":" ((peg/match ~(* (any " ") (capture (* :d :d ":" :d :d)) (any " ") -1) item-string) 0))
            hours (scan-number (components 0))
            minutes (scan-number (components 1))]
            (def begin (merge tdy {:hours hours :minutes minutes :seconds 0}))
            {:begin begin :duration :unknown :end :unknown :exact true})
    (peg/match ~(* "<" :d :d ":" :d :d)) ))

(defn parse-log-item
  "Parses a log item and outputs a struct describing the time period for task, its completeness status and its description"
  [log-item-string &opt tdy]
  (default tdy (date/today-local))
  (def parsed (peg/match patt_log_item log-item-string))
  (cond
    (= (length parsed) 1) {:description (parsed 0)}
    (= (length parsed) 2) (merge {:description (parsed 1)} (parse-log-item-time (parsed 0) tdy))
    (error "Invalid log item")))
  #TODO parse datetime string into following struct: {:from date_here :to date_here :duration duration_here_only_if_needed)}
  #date_here can be :beginning_of_time :end_of_time a date struct formatted like (os/date)

