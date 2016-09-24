#!/bin/sh

# Take screenshot in Qubes Dom0, auto copy to AppVM, upload to imgurl service
# Dependencies: scrot at dom0 (sudo qubes-dom0-update scrot) 
# zenity at dom0 and at AppVM (already exists by default at fedora and dom0)

# (c) EvaDogStar 2016 

version="0.5beta"
DOM0_SHOTS_DIR=$HOME/Pictures
APPVM_SHOTS_DIR=/home/user/Pictures
QUBES_DOM0_APPVMS=/var/lib/qubes/appvms/
IMGURL_LOG="imgurl.log"
LAST_ACTION_LOG_CONFIG="$HOME/.config/qvm-screenshot-lastaction.cfg"

rightdom0dir=$(xdg-user-dir PICTURES)
if [[ "$rightdom0dir" =~ ^/home/user* ]]; then
DOM0_SHOTS_DIR=$rightdom0dir
fi

TEMPEDITORFILE="$DOM0_SHOTS_DIR/0000-SAVE-EDITED-SHOT-HERE-TO-PROCESS.png"

UPLOADHELPER=$(cat <<'EOFFILE'
#!/bin/bash
# Eva Dog Star imgurl uploader
imgur_anon_id="ea6c0ef2987808e"
# check arguments
if [ $# == 0 ]; then
   echo "[ERROR] No file specified" >&2
   exit 16
fi
# check curl is available
type curl >/dev/null 2>/dev/null || {
   echo "[ERROR] Couln't find curl, which is required at AppVM." >&2
   exit 17
}
file="$1"
logfile="$2"   
   # check file exists
   if [ ! -f "$file" ]; then
      echo "[ERROR] file '$file' doesn't exist at AppVM" >&2
      exit 18
   fi
   response="$(curl --compressed --connect-timeout "7" -m "250" --retry "1" -fsSL --stderr - -H "Authorization: Client-ID ${imgur_anon_id}" -F "image=@$file" https://api.imgur.com/3/image)"
   if egrep -q '"success":\s*true' <<<"${response}"; then
       img_id="$(egrep -o '"id":\s*"[^"]+"' <<<"${response}" | cut -d "\"" -f 4)"
       img_ext="$(egrep -o '"link":\s*"[^"]+"' <<<"${response}" | cut -d "\"" -f 4 | rev | cut -d "." -f 1 | rev)" # "link" itself has ugly '\/' escaping and no https!
       del_id="$(egrep -o '"deletehash":\s*"[^"]+"' <<<"${response}" | cut -d "\"" -f 4)"
       imgurl="https://i.imgur.com/${img_id}.${img_ext}"
       imgdeleteurl="https://imgur.com/delete/${del_id}"
      echo -e "Image url:\n$imgurl\n\nDelete image url: \n$imgdeleteurl\n\n \nQubes Screenshot Tool - EvaDogStar 2016" > $logfile
      echo "[success] imgurl: $imgurl" >&2   
      echo "[success] delete url: $imgdeleteurl" >&2
   else # upload failed
       err_msg="$(egrep -o '"error":\s*"[^"]+"' <<<"${response}" | cut -d "\"" -f 4)"
       test -z "${err_msg}" && err_msg="${response}"
       echo "[ERROR] $err_msg"
       echo "[RESPONSE] $response" 
     echo -e "Error: \n\n$err_msg \n\nImgurl Server response: \n\n$response\n\n\n \nQubes Screenshot Tool - EvaDogStar 2016" > $logfile       
       #echo ${err_msg}
   fi
(which xclip &>/dev/null && echo -n "$imgurl" | xclip -selection clipboard ) || echo "[NOTE] no xclip at AppVM"
      
EOFFILE
)

write_last_action_config()
{
touch "$LAST_ACTION_LOG_CONFIG"
cat <<EOF > $LAST_ACTION_LOG_CONFIG
# last app vm used to upload image
appvm=$appvm
logfile=$logfile
EOF
}

read_last_action_config()
{

[ -e $LAST_ACTION_LOG_CONFIG ] && source $LAST_ACTION_LOG_CONFIG

open_imgulr_upload_dialog_at_destination_appvm

if [ "$appvm" == "" ]; then
      printf "Last action not available \n" 
      zenity --info --modal --text "Last action not available. Please, upload some image with this AppVM first." &>/dev/null
fi

exit 1
}

open_imgulr_upload_dialog_at_destination_appvm()
{
   qvm-run $appvm "zenity --text-info --width=500 --height=180 --modal --filename=$logfile --text Ready"
}

checkscrot()
{  
   (which scrot &>/dev/null ) || { 
      scrotnomes="[EXIT] no \"scrot\" tool at dom0 installed use: \n\nsudo qubes-dom0-update scrot \n\ncommand to add it first"
      printf "$scrotnomes\n" 
      zenity --info --modal --text "$scrotnomes" &>/dev/null
      exit 1 
   }
}

start_ksnapshoot()
{
  PID="$(pgrep ksnapshot)"
  if [ "$PID" == "" ]; then
   ksnapshot &
   sleep 1
  fi
  # setGrabMode notes: 0=full-screen, 1=window, 2=region
  #kstart ksnapshot
  #kdialog --radiolist "Now you can user Snapshot tool to make screenshots. When and only when you will be ready with screenshot (check preview area) click OKEY. Confirm only if you are ready!" READY READY READY --default continue --title "$program" --nograb --noxim  
  zenity --question --text "Move this window away and make screenshot. When you are ready to upload image click OK"
  
  # while [ "$PID" == "" ]; do PID="$(pgrep -n ksnapshot)"; done

  # ksnap pid changed after using region selection tool
  PID="$(pgrep ksnapshot)"
  program="org.kde.ksnapshot-${PID}"
  qdbus $program /KSnapshot save $2
  printf "[+] ksnapshot saved at: $2\n"
  qdbus $program /KSnapshot exit
}


# check dependencies
 (which zenity &>/dev/null ) || { 
    warn="[FATAL] no \"zenity\" tool at dom0 installeted use: \n\nsudo qubes-dom0-update zenity command to add it first"
    printf "$warn\n"
    exit 1 
 }

 (which display &>/dev/null ) || { 
    warn="[EXIT] no \"ImageMagic\" (display) package at dom0 installeted use: \n\nsudo qubes-dom0-update ImageMagic \n\ncommand to add it first"
    printf "$scrotnomes\n" 
    zenity --info --modal --text "$warn" &>/dev/null
    exit 1 
 }

program="`basename $0`"
shotslist=""

mkdir -p $DOM0_SHOTS_DIR ||exit 1
while true; do
   d=`date +"%Y-%m-%d-%H%M%S"`
   shotname=$d.png

# check ksnapshoot exists
  ksnapshottxt="FALSE Ksnapshot"

  (which ksnapshot &>/dev/null ) || { 
     ksnapshottxt=""
  }


   ans=$(zenity --list --modal --text "Choose capture mode of capturing \n Use:" --radiolist --column "Pick" --column "Option" \
   $ksnapshottxt \
   TRUE "Region or Window" \
   FALSE "Fullscreen" \
   FALSE "Open last dialog" \
   ) 

#   echo $ans

  if [ X"$ans" == X"Ksnapshot" ]; then
   printf "[+] starting ksnapshot..."
   start_ksnapshoot 4 $DOM0_SHOTS_DIR/$shotname || break
  elif [ X"$ans" == X"Region or Window" ]; then
     checkscrot || break
     echo "[+] capturing window, click on it to select"
     scrot -s -b $DOM0_SHOTS_DIR/$shotname || break
  elif [ X"$ans" == X"Fullscreen" ]; then
     checkscrot || break
     echo "[+] capturing fullscreen desktop"      
     scrot -b $DOM0_SHOTS_DIR/$shotname || break
  elif [ X"$ans" == X"Open last dialog" ]; then
     echo "[+] opening last dialog at AppVM with uploaded urls if exists"
     read_last_action_config || break
     exit 1
  else
     echo "You must select some mode to continue" && exit 1
  fi

  if [ -f "$DOM0_SHOTS_DIR/$shotname" ]
  then
      echo "[+] Success at dom0. Screenshot saved at $DOM0_SHOTS_DIR/$shotname" || break
  else
   echo "[ERROR] Something has gone wrong and screenshot has not been saved at dom0."
   $(zenity --info --modal --text "Something has gone wrong and screenshot has NOT been saved at dom0") 
   exit 12
  fi


   shotslist="$shotname"
   #shotslist="${shotslist}${shotname}:"
   break
done


  
 ans=$(zenity --list --modal --width=200 --height=290 --text "Screenshot saved at dom0 \nWhat do you want to do next?\nSelect or multiselect some options:" --checklist --column "Pick" --column "Options" \
   FALSE Exit \
   FALSE "Upload to AppVM only" \
   FALSE "Edit Screenshot" \
   FALSE "Upload to Imgurl" \
   FALSE "Start Nautilus at AppVM" \
   FALSE "Keep screenshot at dom0"
   ) 
   #echo "xxx $ans xxx"

[[ X"$ans" == X"" ]] && exit 1

mode_exit=0
mode_onlyupload=0
mode_edit=0
mode_nautilus=0
mode_imgurl=0
mode_not_delete_screen_at_dom=0

IFSDEFAULT=$IFS
IFS='|'; for val in $ans; 
do 
#echo "variable: $val and $1"
case $val in
  'Exit') mode_exit=1;exit 1 ;;
  'Upload to AppVM only') mode_onlyupload=1;  ;;
  'Edit Screenshot') mode_edit=1;  ;;
  'Upload to Imgurl') mode_imgurl=1;  ;;
  'Start Nautilus at AppVM') mode_nautilus=1;  ;;
  'Keep screenshot at dom0') mode_not_delete_screen_at_dom=1;  ;;
 # -r) mode_region=1;  ;;
  *) echo "Never Good Bye!"; exit 1 ;;
esac done


# editing screenshot with IM
if [ $mode_edit -eq 1 ]; then
  echo "[-] editing screenshot started. Click on the image to get the edit menu. Use the tool. When you will be ready save the screenshot to predefined place. Then Exit from IM to continue"

  echo "" > $TEMPEDITORFILE
  display "$DOM0_SHOTS_DIR/$shotname"

  # check if user save his image changes to special SAVE slot that we monitor
 size=$(stat --printf="%s" $TEMPEDITORFILE )
 # if [ $size -ge 20 ]; then
 #   # user stored new image
 # fi  
  if [ $size -ge 20 ]; then
     # user stored new image
     echo "[+] changed screenshot found. Continue with it"
     mv $TEMPEDITORFILE $DOM0_SHOTS_DIR/$shotname
   else
    #clianup tempfile
    rm $TEMPEDITORFILE 
  fi  


  sleep 1
  echo "[-] thanks for editing. Now we continue."  
fi

if [ $mode_edit -eq 1 ]; then
  echo "[+] Good Bye!"
fi

IFS=$IFSDEFAULT
choiceappvm=`ls $QUBES_DOM0_APPVMS |sed 's/\([^ ]*\)/FALSE \1 /g'`
#appvm=`kdialog --radiolist "Select destination AppVM" $choice --title "$program"`
appvm=$(zenity --list --modal  --width=200 --height=390  --text "Select destination AppVM (unix based):" --radiolist --column "Pick" --column "AppVM" $choiceappvm ) 
#echo $appvm


if [ X"$appvm" != X"" ]; then

   echo "[-] start AppVM: $appvm"
   destdir=$(qvm-run -a --pass-io $appvm "xdg-user-dir PICTURES")
   if [[ "$destdir" =~ ^/home/user* ]]; then
    APPVM_SHOTS_DIR=$destdir
   fi

   qvm-run $appvm "mkdir -p $APPVM_SHOTS_DIR"

   if [ $mode_nautilus -eq 1 ]; then
      echo "[-] running nautilus in AppVM"
      qvm-run $appvm "nautilus $APPVM_SHOTS_DIR"
      sleep 1
   fi

   shot=$shotslist

   echo "[-] copying screenshot to $APPVM_SHOTS_DIR/$shot"
   cat $DOM0_SHOTS_DIR/$shot \
      |qvm-run --pass-io $appvm "cat > $APPVM_SHOTS_DIR/$shot"

   [[ $mode_not_delete_screen_at_dom -eq 1 ]] && rm -f $DOM0_SHOTS_DIR/$shot && echo "[+] Screen at dom0 deleted $DOM0_SHOTS_DIR/$shot"
   [[ $mode_onlyupload -eq 1 ]] && exit 1


   [[ $mode_imgurl -eq 0 ]] && exit 1

   echo "[-] copying imgurl uploader to AppVM $appvm"
#      echo $UPLOADHELPER \
#          | qvm-run --pass-io $appvm "echo $UPLOADHELPER > $APPVM_SHOTS_DIR/autouplodertemp.sh"
   uploadername='evauploadermgur.sh'
   logfile="$APPVM_SHOTS_DIR/$IMGURL_LOG"
   echo "$UPLOADHELPER" | qvm-run --pass-io $appvm "cat > $APPVM_SHOTS_DIR/$uploadername"
   qvm-run --pass-io $appvm "chmod +x $APPVM_SHOTS_DIR/$uploadername"
   RESULT="$(qvm-run --pass-io $appvm "$APPVM_SHOTS_DIR/$uploadername $APPVM_SHOTS_DIR/$shot $logfile")"
   qvm-run $appvm "rm $APPVM_SHOTS_DIR/$uploadername"
   #qvm-run $appvm "gedit $logfile" 
   
   open_imgulr_upload_dialog_at_destination_appvm

   echo $RESULT

   # write AppVM name and log file at AppVM to the dom0 config to open it again
   write_last_action_config

   #done
else
   echo "[-] no AppVM name provided"
fi

echo "[*] Dom0 say Good Bye"
