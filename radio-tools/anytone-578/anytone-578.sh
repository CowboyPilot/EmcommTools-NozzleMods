#!/bin/bash
#
# Purpose : Audio settings specific to the Anytone 578 w/ Digirig Mobile
#
# Preconditions
# 1. Supported audio interface is connected and properly detected
#
# Postconditions
# 1. ALSA settings set on ET audio device

usage() {
  echo "usage: $(basename $0) <ET audio card> <ET device name>"
}

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

AUDIO_CARD=$1
ET_DEVICE_NAME=$2

# Unmute Speaker and set the volume to 21%. Adjust if the remote station
# can't decode you or if there is no output power on TX.
amixer -q -c ${AUDIO_CARD} sset Speaker Playback Switch 21% unmute

# Mute Mic Playback
amixer -q -c ${AUDIO_CARD} sset Mic Playback Switch 00% mute

# Set Mic Capture to 13%. Adjust if you can't decode received audio.
amixer -q -c ${AUDIO_CARD} sset Mic Capture Switch 13% unmute

# Disable Auto Gain Control
amixer -q -c ${AUDIO_CARD} sset 'Auto Gain Control' mute

et-log "Applied amixer settings for audio card ${AUDIO_CARD} on device ${ET_DEVICE_NAME}"
