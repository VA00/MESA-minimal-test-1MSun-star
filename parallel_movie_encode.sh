#!/bin/bash
# Osobny film AVI dla kazdego typu wykresu z katalogu png/, wszystkie rownolegle.
# ffmpeg jest czescia MESA SDK (po source $MESASDK_ROOT/bin/mesasdk_init.sh).
dt=$(date '+%Y%m%d%H');
echo "$dt"
for t in trho_profile Kippenhahn HR Network Summary_Burn abund power track1
do
    # wykresy wylaczone w inlist.pgstar nie maja plikow: pomijamy
    compgen -G "png/${t}_*.png" > /dev/null || continue
    ffmpeg -loglevel error -y -framerate 60 -f image2 -pattern_type glob -i "png/${t}_*.png" \
        -c:v libx264 -crf 20 -pix_fmt yuv420p -aspect 16:9 "${t}_${dt}.avi" &
done
wait
echo "Finished all"
