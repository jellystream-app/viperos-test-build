# ~/.bashrc - ViperOS
#
# Wird fuer jede interaktive Shell gelesen. Die Datei liegt in /etc/skel und
# wird damit fuer jeden neuen Benutzer angelegt - auch fuer den, den
# Calamares bei der Installation erstellt.

# Nur fuer interaktive Shells fortfahren.
case $- in
    *i*) ;;
      *) return;;
esac

# --- Verlauf ---
HISTCONTROL=ignoreboth
HISTSIZE=2000
HISTFILESIZE=5000
shopt -s histappend
shopt -s checkwinsize

# --- Eingabeaufforderung ---
# Benutzer gruen, Pfad blau - passend zum ViperOS-Akzent.
if [ -n "${debian_chroot:-}" ]; then
    PS1='(${debian_chroot})\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
fi

# --- Farben ---
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# --- Abkuerzungen ---
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias cls='clear'
alias update='sudo apt update && sudo apt upgrade -y'
alias install='sudo apt install -y'
alias search='apt search'

# --- bash-completion ---
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# --- Systemuebersicht beim Oeffnen eines Terminals ---
# fastfetch nutzt /etc/fastfetch/config.jsonc und damit das ViperOS-Logo.
# Nur in einer echten interaktiven Sitzung, nicht in Skripten oder
# ueber SSH-Kommandos.
if [ -t 1 ] && command -v fastfetch >/dev/null 2>&1; then
    fastfetch
fi
