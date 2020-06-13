#!/bin/bash
#___h_sys.sh___

source h_log.sh
# log_sys "er" "blędna informacja"
# log_sys "poprawna informacja"
# log_gp "er" GPIO STAN "blędna informacja"
# log_gp GPIO STAN "poprawna informacja"

SYS_NUM=0
SYS_ID[0]=0
SYS_COM[0]=""
SYS_VAL[0]=0

function sys_init(){
    if [ $SYS_NUM -gt 1 ] ; then
        for (( i=1 ; i<SYS_NUM ; i++ )) ; do
            unset SYS_ID[$i]
            unset SYS_COM[$i]
            unset SYS_VAL[$i]
        done
    fi
    local tmp=$(echo "SELECT COUNT(1) FROM cnf WHERE syst=1 ORDER BY id" | mysql -D$DB -u $USER -p$PASS -N)
    SYS_NUM=${tmp[0]}
    if [ $SYS_NUM -gt 0 ] ; then
        tmp=$(echo "SELECT id FROM cnf WHERE syst=1 ORDER BY id" | mysql -D$DB -u $USER -p$PASS -N)
        SYS_ID=( $( for i in $tmp ;do echo $i ;done ) )
        tmp=$(echo "SELECT comm FROM cnf WHERE syst=1 ORDER BY id" | mysql -D$DB -u $USER -p$PASS -N)
        SYS_COM=( $( for i in $tmp ;do echo $i ;done ) )
        tmp=$(echo "SELECT valu FROM cnf WHERE syst=1 ORDER BY id" | mysql -D$DB -u $USER -p$PASS -N)
        SYS_VAL=( $( for i in $tmp ;do echo $i ;done ) )
    fi
}

function sys_restart(){
    log_sys "RESTART systemu"
    sudo reboot
}

function sys_power_off(){
    log_sys "WYŁĄCZENIE systemu"
    sudo shutdown now
}
