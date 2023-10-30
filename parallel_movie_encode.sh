#!/bin/bash
dt=$(date '+%Y%m%d%H');
echo "$dt"
mencoder -really-quiet -fps 60 -aspect 16/9 -mf type=png mf://png/trho_profile_*.png -ovc x264 -oac copy -o "trho_profile_${dt}.avi" &
mencoder -really-quiet -fps 60 -aspect 16/9 -mf type=png mf://png/Kippenhahn_*.png   -ovc x264 -oac copy -o "Kippenhahn_${dt}.avi" &
mencoder -really-quiet -fps 60 -aspect 16/9 -mf type=png mf://png/HR_*.png           -ovc x264 -oac copy -o "HR_${dt}.avi" &
mencoder -really-quiet -fps 60 -aspect 16/9 -mf type=png mf://png/Network_*.png      -ovc x264 -oac copy -o "Network_${dt}.avi" &
mencoder -really-quiet -fps 60 -aspect 16/9 -mf type=png mf://png/Summary_Burn_*.png -ovc x264 -oac copy -o "Summary_Burn_${dt}.avi" &
mencoder -really-quiet -fps 60 -aspect 16/9 -mf type=png mf://png/abund_*.png        -ovc x264 -oac copy -o "abund_${dt}.avi" &
mencoder -really-quiet -fps 60 -aspect 16/9 -mf type=png mf://png/power_*.png        -ovc x264 -oac copy -o "power_${dt}.avi" &
mencoder -really-quiet -fps 60 -aspect 16/9 -mf type=png mf://png/track1_*.png       -ovc x264 -oac copy -o "track1_${dt}.avi" &
wait
echo "Finished all"
