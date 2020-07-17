#!/bin/bash
#___main.sh___

source h_log.sh #funkcje zapisu informacj zdazen do bazy danych
# log_sys "er" "blędna informacja"
# log_sys "poprawna informacja"
# log_gp "er" GPIO STAN "blędna informacja"
# log_gp GPIO STAN "poprawna informacja"
source h_test.sh #funkcje testujace czas wykonywania skryptu
# start_test
# stop_test
source h_prog.sh
source h_sys.sh
source h_weather.sh


function main(){
    log_sys "START SYSTEMU"

    while [ 1 ] ; do
        #start_test
        #weather_event
        prog_event
        #stop_test
        if [ $PR_ID -lt 0 ] ; then
            sys_event
        fi
        sleep 1
        if [ $SYS_RELOAD -eq 1 ] ; then
            log_sys "PRZEŁADOWANIE usługi systemowej"
            mysql -D$DB -u $USER -p$PASS -N -e"UPDATE cnf SET valu=0 WHERE comm='reload';"
            SYS_RELOAD=0
            sudo systemctl restart homster.service
        fi
    done
}
main
