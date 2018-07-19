#!/bin/sh

# Modem device
DEV=/dev/ttyACM0
LOCK_FILE=/tmp/sms-lock
#AT&F&C1&D2

if [ -f $LOCK_FILE ]; then
	LOCK_PID="$(cat $LOCK_FILE)"
	while [ -d /proc/$LOCK_PID ]; do
		echo "Lock detected! Waiting ..."
		sleep 1
	done
fi
echo $$ > $LOCK_FILE

function get_sms_status() {
	while true; do
		if read -t 10 line; then
			if $(echo "$line" | grep -q '^+CMS ERROR'); then
				echo "fail"
				return 1
			fi
			if $(echo "$line" | grep -q '^+CMGS: [0-9]\+'); then
				echo "success"
				return 0
			fi
		else
			echo "timeout"
			return 2
		fi
	done < $DEV
}

get_sms_status &
pid=$!

PHONE="$1"
TEXT="$2"

# we need to put sleep 1 to slow down commands for modem to process
echo -e "ATZ\r" > $DEV
sleep 1
echo -e "AT+CMGF=1\r" > $DEV
sleep 1
echo -e "AT+CMGS=\"$PHONE\"\r" > $DEV
sleep 1
echo -e "$TEXT\x1A\r" > $DEV

echo "PID: $pid"
wait $pid
status="$?"

rm -f $LOCK_FILE
echo "status: $status"
exit $status
