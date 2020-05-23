#!/usr/bin/env bash
export HOMEBREW_CELLAR=/home/linuxbrew/.linuxbrew/Cellar
export HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
export HOMEBREW_REPOSITORY=/home/linuxbrew/.linuxbrew/Homebrew

if [ -z "${INFOPATH}" ]; then
	export INFOPATH=/home/linuxbrew/.linuxbrew/share/info
else
	if [ -z $(echo ":${INFOPATH}:" | egrep ".*:/home/linuxbrew/\.linuxbrew/share/info:.*") ]; then
		export INFOPATH="/home/linuxbrew/.linuxbrew/share/info:${INFOPATH}"
	fi
fi

if [ -z "${MANPATH}" ]; then
	export MANPATH=/home/linuxbrew/.linuxbrew/share/man
else
	if [ -z $(echo ":${MANPATH}:" | egrep ".*:/home/linuxbrew/\.linuxbrew/share/man:.*") ]; then
		export MANPATH="/home/linuxbrew/.linuxbrew/share/man:${MANPATH}"
	fi
fi

if [ -z $(echo ":${PATH}:" | egrep ".*:/home/linuxbrew/\.linuxbrew/sbin:.*") ]; then
	PATH="/home/linuxbrew/.linuxbrew/sbin:${PATH}"
fi

if [ -z $(echo ":${PATH}:" | egrep ".*:/home/linuxbrew/\.linuxbrew/bin:.*") ]; then
	PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
fi
