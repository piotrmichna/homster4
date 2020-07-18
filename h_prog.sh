#!/bin/bash
#___h_prog.sh___

source h_log.sh #funkcje zapisu informacj zdazen do bazy danych
# log_sys "er" "blędna informacja"
# log_sys "poprawna informacja"
# log_gp "er" GPIO STAN "blędna informacja"
# log_gp GPIO STAN "poprawna informacja"
source h_prog_gpio.sh
# gpio_get_data #pobiera pramtry gpio z mysql
# gpio_list # wyswietla na ekranie liste dostepnych portow
# gpio_init # pobiera parametry gpio z mysql i inicjuje gpio
source h_test.sh #funkcje testujace czas wykonywania skryptu
# start_test
# stop_test

TNOW=$(date +"%T") #zminna zawierający aktualny czas
NEW_DAY=-1
PR_START_NUM=-1
PR_NEXT_TIM=""
PR_NEXT_TIM_SEC=0
PR_NEXT_TIM_CNT=-1
PR_NEXT_TIM_ELSP=""
PR_NEXT_PROG_ID=-1
PR_ID=-1
PR_NAZ=""
PR_SENS_OK=1
PR_ITEM_NUM=0
PR_ITEM_LP=-1
PR_ITEM_ID[0]=0
PR_ITEM_PAR[0]=0
PR_ITEM_DELAY[0]=0
PR_ITEM_CNT[0]=0
PR_ITEM_GPID[0]=0

function end_prog(){
    log_sys "KONIEC programu [ $PR_NAZ ]"
    PR_NEXT_TIM=""
    PR_NEXT_TIM_SEC=-1
    PR_NEXT_TIM_CNT=-1
    PR_NEXT_TIM_ELSP=""
    PR_NEXT_PROG_ID=-1
    PR_ID=-1
    PR_NAZ=""
    # zmienne urzadzen
    PR_SENS_OK=1
    PR_ITEM_LP=-1
    for (( i=0 ; i<PR_ITEM_NUM ; i++ )) ; do
        if [ ${GP_DIR[${PR_ITEM_GPID[$i]}]} -eq 1 ] ; then
            #wylacz wyjscie
            gpo_out "$i" "0"
        fi
        if [ $i -gt 0 ] ; then
            unset PR_ITEM_ID[$i]
            unset PR_ITEM_PAR[$i]
            unset PR_ITEM_DELAY[$i]
            unset PR_ITEM_CNT[$i]
            unset PR_ITEM_GPID[$i]
        fi
    done
    PR_ITEM_NUM=0
    PR_ITEM_ID[0]=0
    PR_ITEM_PAR[0]=0
    PR_ITEM_DELAY[0]=0
    PR_ITEM_CNT[0]=0
    PR_ITEM_GPID[0]=0

    if [ $PR_START_NUM -gt 0 ] ; then # sprawdz czy jest kolejny start
        get_next_start
    fi
}

function gpo_out(){
    # gpo_out LP STAN
    if [ -z ${1+x} ] && [ -z ${2+x} ] ; then
        log_sys "er" "fun. gpo_out bez podania parametrów"
    else
        local GID=${PR_ITEM_GPID[$1]}
        local STAN=$2
        if [ ${GP_STAN_ACT[$GID]} -ne 1 ] ; then
            if [ $STAN -eq 1 ] ; then
                STAN=0
            else
                STAN=1
            fi
        fi
        if [ ${GP_DIR[$GID]} -eq 1 ] ; then
            if [ $STAN -ne ${GP_STAN[$GID]} ] ; then # zmiana stanu wyjscia jest mozliwa
                 gpio write ${GP_GPIO[$GID]} $STAN
                 GP_STAN[$GID]=$STAN
                 mysql -D$DB -u $USER -p$PASS -N -e"UPDATE item SET stan=$STAN WHERE id=${GP_ID[$GID]};"
                if [ $2 -eq 1 ] ; then # stan ON
                    log_gp "${GP_GPIO[$GID]}" "$STAN" "${GP_NAZ[$GID]} - on"
                else # stan OFF
                    log_gp "${GP_GPIO[$GID]}" "$STAN" "${GP_NAZ[$GID]} - off"
                fi #stan
            else
                # gpio nie jest wyjsciem
                log_gp "er" "${GP_GPIO[$GID]}" "$STAN" "${GP_NAZ[$GID]} - ponowny ustawienie stanu"
            fi
        else
            log_gp "er" "${GP_GPIO[$GID]}" "$STAN" "${GP_NAZ[$GID]} - nie jest wyscie"
        fi
    fi
}

function sensor(){
    if [ -z ${1+x} ] ; then
        log_sys "er" "sensor bez parametru"
    else
        if [ ${PR_ITEM_CNT[$1]} -eq 0 ] ; then
            #sprawdzenie stanu senasora
            local ret=$( gpio read ${GP_GPIO[${PR_ITEM_GPID[$1]}]} )
           # echo "sensor$1 = $ret byl ${GP_STAN[${PR_ITEM_GPID[$1]}]}"
            #if [ $ret -ne ${GP_STAN[${PR_ITEM_GPID[$1]}]} ] ; then # wykryto zmiane stanu sensora
                GP_STAN[${PR_ITEM_GPID[$1]}]=$ret
                if [ $ret -eq ${GP_STAN_ACT[${PR_ITEM_GPID[$1]}]} ] ; then
                    PR_SENS_OK=1
                    log_gp "${GP_GPIO[${PR_ITEM_GPID[$1]}]}" "$ret" "zmiana - stan poprawny"
                else
                    PR_SENS_OK=0
                    log_gp "${GP_GPIO[${PR_ITEM_GPID[$1]}]}" "$ret" "zmiana - stan negatywny"
                fi
                mysql -D$DB -u $USER -p$PASS -N -e"UPDATE item SET stan=$ret WHERE id=${GP_ID[${PR_ITEM_GPID[$1]}]};"
            #fi
            PR_ITEM_CNT[$1]=${PR_ITEM_DELAY[$1]}
        else
            PR_ITEM_CNT[$1]=$((PR_ITEM_CNT[$1]-1))
        fi
    fi
}

function run_prog() {
    for (( n=0 ; n<PR_ITEM_NUM ; n++ )) ; do
        if [ $PR_ITEM_LP -eq $n ] ; then #wywolanie dla kolejnych etapow programu
            if [ ${GP_DIR[${PR_ITEM_GPID[$n]}]} -eq 1 ] ; then
                #instrukcje dla wyjscia
                echo "item_ctn=${PR_ITEM_CNT[$n]} delay=${PR_ITEM_DELAY[$n]}"
                if [ ${PR_ITEM_CNT[$n]} -lt ${PR_ITEM_DELAY[$n]} ] ; then
                    # wysterowanie wyjscia gdy cnt=0
                    if [ ${PR_ITEM_CNT[$n]} -eq 0 ] ; then
                        gpo_out "$n" "1"
                        #skok do nastpnego kroku jesli wyscie jest rownolegle
                        PR_ITEM_CNT[$n]=$(( PR_ITEM_CNT[$n]+1 ))
                        if [ ${PR_ITEM_PAR[$n]} -eq 1 ] ; then
                            PR_ITEM_LP=$(( PR_ITEM_LP+1 ))
                        else
                            # odliczanie czasu delay cnt<delay
                            break
                        fi
                    else
                        # odliczanie czasu delay cnt<delay
                        PR_ITEM_CNT[$n]=$(( PR_ITEM_CNT[$n]+1 ))
                        break
                    fi
                else
                    # wylaczenie wyjscia cnt=delay
                    gpo_out "$n" "0"
                    PR_ITEM_LP=$(( PR_ITEM_LP+1 ))
                fi
            else
                #instrukcje dla wejsc
                sensor "$n"
                if [ $PR_SENS_OK -eq 0 ] ; then
                    #przerwanie dzialania programu
                    log_sys "er" "STOP z sensora ${GP_NAZ[${PR_ITEM_GPID[$n]}]} w lp=$PR_ITEM_LP"
                    end_prog
                    break
                fi
                PR_ITEM_LP=$(( PR_ITEM_LP+1 ))
            fi
        else # wywolanie dla etapow poprzednich i ciaglych
            #czynnosci rownolegle z poprzednich krokow
            if [ ${PR_ITEM_PAR[$n]} -eq 1 ] ; then
                if [ ${GP_DIR[${PR_ITEM_GPID[$n]}]} -eq 0 ] ; then
                     #instrukcje dla wejsc
                    sensor "$n"
                    if [ $PR_SENS_OK -eq 0 ] ; then
                        #przerwanie dzialania programu
                        log_sys "er" "STOP z sensora ${GP_NAZ[${PR_ITEM_GPID[$n]}]} w lp=$PR_ITEM_LP"
                        end_prog
                        break
                    fi
                fi
            fi
        fi
    done
}

function get_prog_item(){
    local tmp=$(echo "SELECT itemid FROM prog_item WHERE progid=$PR_ID ORDER BY lp" | mysql -D$DB -u $USER -p$PASS -N)
    PR_ITEM_ID=( $( for i in $tmp ;do echo $i ;done ) )

    tmp=$(echo "SELECT parale FROM prog_item WHERE progid=$PR_ID ORDER BY lp" | mysql -D$DB -u $USER -p$PASS -N)
    PR_ITEM_PAR=( $( for i in $tmp ;do echo $i ;done ) )

    tmp=$(echo "SELECT delay_s FROM prog_item WHERE progid=$PR_ID ORDER BY lp" | mysql -D$DB -u $USER -p$PASS -N)
    PR_ITEM_DELAY=( $( for i in $tmp ;do echo $i ;done ) )
    # pobieranie wlasnosci item
    for (( i=0 ; i<PR_ITEM_NUM ; i++ )) ; do
        for (( j=0 ; j<GP_NUM ; j++ )) ; do
            if [ ${GP_ID[$j]} -eq ${PR_ITEM_ID[$i]} ] ; then
                PR_ITEM_GPID[$i]=$j
                PR_ITEM_CNT[$i]=0
                break
            fi
        done
    done
    # zerowanie kolejnosci elementow programu
    PR_ITEM_LP=0
}

function begin_prog(){
    if [ $PR_ID -gt 0 ] ; then
        local tmp=$(echo "SELECT COUNT(1) FROM prog_item WHERE progid=$PR_ID" | mysql -D$DB -u $USER -p$PASS -N)
        PR_ITEM_NUM=${tmp}
        echo "item num=$PR_ITEM_NUM"
        if [ $PR_ITEM_NUM -gt 0 ] ; then
            tmp=$(echo "SELECT nazwa FROM prog WHERE id=$PR_ID" | mysql -D$DB -u $USER -p$PASS -N)
            PR_NAZ=${tmp[0]}
            log_sys "START programu [ $PR_NAZ ]"
            get_prog_item
        else
            log_sys "er"  "wywolanie pustego programu"
            end_prog
        fi
    else
        log_sys "KONIEC programu [ $PR_NAZ ]"
        end_prog
    fi
}

function sec_to_str(){
    local T=$1
    local H=$(( T/3600 ))
    local X=$(( H*3600 )) ; T=$(( T-X ))
    local M=$(( T/60 )) ; X=$(( M*60 )) ; T=$(( T-X ))
    local S=$(( T%60 ))

    if [ $H -lt 10 ] ; then local tim_str=$(echo "0$H:") ; else local tim_str=$(echo "$H:") ; fi
    if [ $M -lt 10 ] ; then tim_str=$(echo "${tim_str}0$M:") ; else tim_str=$(echo "${tim_str}$M:") ; fi
    if [ $S -lt 10 ] ; then tim_str=$(echo "${tim_str}0$S") ; else tim_str=$(echo "${tim_str}$S") ; fi
    echo "$tim_str"
}

function is_time_now(){
    local TIX=`date --date="$1" +%s`
    local TN=$(date +"%T")
    local TNW=`date --date="$TN" +%s`
    local TE=$(( TIX-TNW ))
    PR_NEXT_TIM_SEC=$TE
    PR_NEXT_TIM_ELSP=$( sec_to_str $TE )
    echo "$TE"
}

function get_next_start(){
    log_sys "TIME - szukanie nastepnych uruchomień"
    local TNOW=$(date +"%T")
    local tmp=$(echo "SELECT COUNT(1) FROM start_time WHERE tim>'$TNOW' ORDER BY tim" | mysql -D$DB -u $USER -p$PASS -N)
    PR_START_NUM=${tmp}
    if [ -z $PR_START_NUM ] ; then
        PR_START_NUM=-1
    fi
    echo "ilosc startow $PR_START_NUM"
    if [ $PR_START_NUM -gt 0 ] ; then
        tmp=$(echo "SELECT tim FROM start_time WHERE tim>'$TNOW' ORDER BY tim LIMIT 1" | mysql -D$DB -u $USER -p$PASS -N)
        PR_NEXT_TIM=${tmp[0]}
        tmp=$(echo "SELECT progid FROM start_time WHERE tim>'$TNOW' ORDER BY tim LIMIT 1" | mysql -D$DB -u $USER -p$PASS -N)
        PR_NEXT_PROG_ID=${tmp[0]}
        PR_NEXT_TIM_SEC=$( is_time_now "$PR_NEXT_TIM" )
        PR_NEXT_TIM_CNT=$(( PR_NEXT_TIM_SEC/2 ))
    else
        PR_NEXT_TIM=""
        R_NEXT_PROG_ID=-1
    fi
    #tsn=`date --date="$TNOW" +%s`
    #tss=`date --date="$PR_NEXT_START_TIM" +%s`
    #tse=$(( tss-tsn ))

    #xt=$( sec_to_str $tse )
    #echo "pozostały czas do startu to: $xt"
}

function wait_for_prog_start(){
    if [ $PR_START_NUM -gt 0 ] ; then # są planowane starty
        if [ $PR_ID -lt 1 ] ; then # oczekiwanie na program
            if [ $PR_NEXT_TIM_SEC -gt 10 ] ; then # ilosc sekund do startu >10
                if [ $PR_NEXT_TIM_CNT -eq 0 ] ; then # akutalizacja ilosci sekund do startu
                    PR_NEXT_TIM_SEC=$( is_time_now "$PR_NEXT_TIM" )
                    PR_NEXT_TIM_CNT=$(( PR_NEXT_TIM_SEC/2 ))
                    echo "wait for program -> sec: $PR_NEXT_TIM_SEC cnt: $PR_NEXT_TIM_CNT  LP=$PR_ITEM_LP"
                else # odliczanie
                    PR_NEXT_TIM_SEC=$(( PR_NEXT_TIM_SEC-1 ))
                    PR_NEXT_TIM_CNT=$(( PR_NEXT_TIM_CNT-1 ))
                fi
            else # ilosc sekund do startu <10
                PR_NEXT_TIM_SEC=$( is_time_now "$PR_NEXT_TIM" )
                echo "wait for program -> sec: $PR_NEXT_TIM_SEC cnt: $PR_NEXT_TIM_CNT  LP=$PR_ITEM_LP"
                if [ $PR_NEXT_TIM_SEC -lt 1 ] ; then
                    PR_ID=$PR_NEXT_PROG_ID
                    #wywolanie planowanego programu
                    begin_prog
                fi
            fi
        fi # oczekiwanie na program
    else # brak startow biezacego dnia
        if [ $NEW_DAY -ne $(date +'%-j') ] ; then # oczekiwanie na nastepny dzien
            if [ $GP_NUM -eq -1 ] ; then
                gpio_init
            fi
            get_next_start
            NEW_DAY=$(date +"%-j")
        fi # ilosc startow
    fi # planowane starty
}

function prog_event(){
    if [ $PR_ITEM_LP -eq -1 ] ; then # program nie aktywny
        wait_for_prog_start
    else # program aktywny
        run_prog
        if [ $PR_ITEM_LP -eq $PR_ITEM_NUM ] ; then
            end_prog
        fi
    fi
}
