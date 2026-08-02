#!/usr/bin/env bash
# =============================================================================
#  setup-zsh.sh - Setup inicial de zsh para VMs Ubuntu
# =============================================================================
#
#  TL;DR - instalacion rapida en una VM Ubuntu recien creada:
#
#      curl -fsSLO https://raw.githubusercontent.com/TU-USUARIO/setup-zsh/main/setup-zsh.sh
#      less setup-zsh.sh        # miralo antes: lo vas a correr como root
#      sudo bash setup-zsh.sh
#      exec zsh
#
#  Y si preferis no traer nada por red, copialo y correlo:
#
#      scp setup-zsh.sh usuario@vm:/tmp/ && ssh usuario@vm 'sudo bash /tmp/setup-zsh.sh'
#
# -----------------------------------------------------------------------------
#  QUE CAMBIA EN EL SISTEMA (leelo antes de correrlo en un server ajeno):
#
#    - instala paquetes con apt: zsh, git, curl y herramientas CLI opcionales
#    - clona Oh My Zsh + 5 plugins en /usr/local/share/oh-my-zsh (compartido)
#    - escribe ~/.zshrc, ~/.zsh_aliases y ~/.p10k.zsh en cada usuario objetivo
#      (si ya tenias un ~/.zshrc propio, lo respalda como .pre-zsh-setup.bak)
#    - CAMBIA EL SHELL POR DEFECTO de esos usuarios y de root a zsh (--no-chsh
#      lo evita)
#    - escribe en /etc/skel, asi todo usuario futuro hereda esta config
#    - toca SHELL= en /etc/default/useradd para que useradd cree usuarios zsh
#    - se copia a /usr/local/sbin/setup-zsh.sh para poder re-correrlo despues
#
#  Nada de esto es destructivo y todo es idempotente: se puede correr N veces.
#
# -----------------------------------------------------------------------------
#  Uso:
#    sudo ./setup-zsh.sh                  # usuario invocante + root + /etc/skel
#    sudo ./setup-zsh.sh --user deploy    # un usuario puntual (repetible)
#    sudo ./setup-zsh.sh --all-users      # todos los usuarios con UID >= 1000
#    sudo ./setup-zsh.sh --no-tools       # solo zsh, sin herramientas CLI extra
#    sudo ./setup-zsh.sh --no-chsh        # no cambia el shell por defecto
#    sudo ./setup-zsh.sh --ascii          # fuerza prompt ASCII (sin Nerd Font)
#    sudo ./setup-zsh.sh --update         # re-sincroniza a las versiones pineadas
#    sudo ./setup-zsh.sh --update --latest  # actualiza al HEAD de cada repo
#
#  Licencia MIT. Instala software de terceros (Oh My Zsh, Powerlevel10k y
#  plugins de zsh-users/Aloxaf), cada uno con su propia licencia MIT/BSD.
# =============================================================================
 
set -Eeuo pipefail
 
# ------------------------------- Configuracion -------------------------------
OMZ_DIR="/usr/local/share/oh-my-zsh"
ZSH_CUSTOM_DIR="${OMZ_DIR}/custom"
SKEL_DIR="/etc/skel"
STATE_FILE="/etc/zsh-setup.version"
SETUP_VERSION="1.1.0"
 
# --- Versiones pineadas ------------------------------------------------------
# Se instala EXACTAMENTE esto, no el HEAD de cada repo: dos VMs deployadas con
# semanas de diferencia quedan identicas, y ningun commit de upstream entra a la
# flota sin que alguien lo apruebe cambiando estas lineas.
#
# Para actualizar: mira los releases del repo, cambia el tag aca, commiteas, y
# corres 'setup-zsh.sh --update' en las VMs. Para probar el HEAD sin pinear,
# usa '--update --latest'.
#
# Oh My Zsh no publica tags, asi que va pineado por commit.
PIN_OMZ="c5ba74cf02cce4c342153f79089100194f30940f"   # master @ 2026-07-30
PIN_P10K="v1.20.0"                                   # romkatv/powerlevel10k
PIN_AUTOSUGGESTIONS="v0.7.1"                         # zsh-users
PIN_SYNTAX_HIGHLIGHTING="0.8.0"                      # zsh-users
PIN_COMPLETIONS="0.36.0"                             # zsh-users
PIN_FZF_TAB="v1.3.0"                                 # Aloxaf/fzf-tab
 
TARGET_USERS=()
DO_ALL_USERS=0
INSTALL_TOOLS=1
DO_CHSH=1
FORCE_ASCII=0
DO_UPDATE=0
USE_LATEST=0
 
# --------------------------------- Helpers -----------------------------------
C_OK=$'\033[0;32m'; C_INFO=$'\033[0;36m'; C_WARN=$'\033[0;33m'
C_ERR=$'\033[0;31m'; C_OFF=$'\033[0m'
[[ -t 1 ]] || { C_OK=""; C_INFO=""; C_WARN=""; C_ERR=""; C_OFF=""; }
 
log()  { printf '%s==>%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s  !!%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }
 
trap 'die "fallo en la linea $LINENO (comando: $BASH_COMMAND)"' ERR
 
have() { command -v "$1" >/dev/null 2>&1; }
 
# Imprime el bloque de comentarios de la cabecera (todo lo que va antes de
# 'set -Eeuo pipefail'), sin el shebang ni los '#' de cada linea.
usage() {
  # Todas las lineas de comentario que siguen al shebang, sin el '#'.
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0" 2>/dev/null \
    || echo "setup-zsh.sh v${SETUP_VERSION} - ver la cabecera del script"
}
 
# ------------------------------ Parseo de flags ------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)      [[ -n "${2:-}" ]] || die "--user requiere un nombre de usuario"
                 TARGET_USERS+=("$2"); shift 2 ;;
    --all-users) DO_ALL_USERS=1; shift ;;
    --no-tools)  INSTALL_TOOLS=0; shift ;;
    --no-chsh)   DO_CHSH=0; shift ;;
    --ascii)     FORCE_ASCII=1; shift ;;
    --update)    DO_UPDATE=1; shift ;;
    --latest)    USE_LATEST=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "opcion desconocida: $1 (usa --help)" ;;
  esac
done
 
# --------------------------- Chequeos preliminares ---------------------------
[[ "$(id -u)" -eq 0 ]] || die "hay que correrlo como root: sudo $0 $*"
have apt-get || die "este script es para Ubuntu/Debian (no encuentro apt-get)"
 
# Usuarios objetivo
if [[ $DO_ALL_USERS -eq 1 ]]; then
  while IFS=: read -r name _ uid _ _ home shell; do
    [[ $uid -ge 1000 && $uid -lt 65534 ]] || continue
    [[ -d "$home" ]] || continue
    [[ "$shell" == */nologin || "$shell" == */false ]] && continue
    TARGET_USERS+=("$name")
  done < /etc/passwd
fi
 
if [[ ${#TARGET_USERS[@]} -eq 0 ]]; then
  # Usuario que invoco sudo, si existe
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USERS+=("$SUDO_USER")
  fi
fi
TARGET_USERS+=("root")
 
# Dedup preservando orden
mapfile -t TARGET_USERS < <(printf '%s\n' "${TARGET_USERS[@]}" | awk '!seen[$0]++')
 
# ============================== 1. Paquetes base ==============================
install_packages() {
  log "Instalando paquetes base"
 
  export DEBIAN_FRONTEND=noninteractive
  # Solo refrescamos el indice si esta viejo (>1 dia) para no perder tiempo
  if [[ -z "$(find /var/lib/apt/lists -maxdepth 1 -type f -mmin -1440 2>/dev/null | head -1)" ]]; then
    apt-get update -qq
  fi
 
  local base=(zsh git curl ca-certificates locales)
  local missing=()
  for p in "${base[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    apt-get install -y -qq --no-install-recommends -o Dpkg::Use-Pty=0 "${missing[@]}" >/dev/null
    ok "instalados: ${missing[*]}"
  else
    ok "paquetes base ya presentes"
  fi
 
  # UTF-8: sin esto el prompt se ve mal
  if ! locale -a 2>/dev/null | grep -qiE '^(C\.utf-?8|en_US\.utf-?8)$'; then
    locale-gen en_US.UTF-8 >/dev/null 2>&1 || true
  fi
}
 
install_cli_tools() {
  [[ $INSTALL_TOOLS -eq 1 ]] || { log "Herramientas CLI: omitidas (--no-tools)"; return 0; }
  log "Instalando herramientas CLI modernas"
 
  export DEBIAN_FRONTEND=noninteractive
  # Se instalan de a una: si un paquete no existe en esta version de Ubuntu,
  # no queremos que se caiga toda la tanda.
  local wanted=(fzf bat ripgrep fd-find eza exa zoxide tree jq htop ncdu unzip)
  local installed=() skipped=()
  for p in "${wanted[@]}"; do
    if dpkg -s "$p" >/dev/null 2>&1; then
      installed+=("$p"); continue
    fi
    if apt-get install -y -qq --no-install-recommends "$p" >/dev/null 2>&1; then
      installed+=("$p")
    else
      skipped+=("$p")
    fi
  done
  [[ ${#installed[@]} -gt 0 ]] && ok "disponibles: ${installed[*]}"
  [[ ${#skipped[@]}   -gt 0 ]] && warn "no disponibles en este Ubuntu: ${skipped[*]} (hay fallback en los aliases)"
 
  # Ubuntu renombra binarios por conflictos de nombre: batcat -> bat, fdfind -> fd
  mkdir -p /usr/local/bin
  if have batcat && ! have bat; then
    ln -sfn "$(command -v batcat)" /usr/local/bin/bat && ok "symlink bat -> batcat"
  fi
  if have fdfind && ! have fd; then
    ln -sfn "$(command -v fdfind)" /usr/local/bin/fd && ok "symlink fd -> fdfind"
  fi
  return 0
}
 
# ============================ 2. Oh My Zsh + plugins ==========================
# Repos en una ubicacion compartida y de solo lectura para los usuarios, cada uno
# fijado a la version de la seccion "Versiones pineadas" de arriba.
#
# No usamos 'git clone --branch' porque eso solo sirve para tags y ramas; con
# init + fetch de un ref puntual podemos pinear por tag O por commit con la misma
# ruta de codigo, y siempre en modo shallow (--depth 1).
fetch_ref() {
  local repo="$1" dest="$2" ref="$3"
  local name; name="$(basename "$dest")"
  local stamp="${dest}/.zsh-setup-ref"
 
  (( USE_LATEST )) && ref="HEAD"
 
  # Ya esta en la version pedida: no hay nada que hacer ni red que tocar.
  # Con --latest siempre re-consultamos, porque HEAD se mueve.
  if [[ -f "$stamp" && "$(cat "$stamp")" == "$ref" && $USE_LATEST -eq 0 ]]; then
    if [[ $DO_UPDATE -eq 0 ]]; then
      ok "$name ya en $ref"
      return 0
    fi
  fi
 
  if [[ ! -d "$dest/.git" ]]; then
    # Puede existir sin ser repo (instalacion vieja o manual). git init es
    # seguro sobre un dir con contenido: no borra nada.
    mkdir -p "$dest"
    git init -q "$dest" || die "no pude inicializar $dest"
  fi
 
  git -C "$dest" remote remove origin 2>/dev/null || true
  git -C "$dest" remote add origin "$repo"
 
  if ! git -C "$dest" fetch -q --depth 1 origin "$ref" 2>/dev/null; then
    die "no pude bajar $name en la version '$ref' (existe ese tag/commit? hay red?)"
  fi
 
  # -f porque venimos de un checkout previo con archivos ya en disco.
  git -C "$dest" checkout -q -f FETCH_HEAD || die "no pude hacer checkout de $name"
 
  echo "$ref" > "$stamp"
  local short; short="$(git -C "$dest" rev-parse --short HEAD 2>/dev/null || echo '?')"
  ok "$name -> ${ref} (${short})"
}
 
install_omz() {
  if (( USE_LATEST )); then
    log "Instalando Oh My Zsh en ${OMZ_DIR} (--latest: HEAD de cada repo)"
    warn "--latest ignora las versiones pineadas: util para probar, no para produccion"
  else
    log "Instalando Oh My Zsh en ${OMZ_DIR} (versiones pineadas)"
  fi
 
  # OJO: OMZ va PRIMERO. custom/ vive adentro y esta en su .gitignore, asi que
  # los plugins sobreviven un cambio de version de OMZ.
  fetch_ref https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DIR" "$PIN_OMZ"
 
  mkdir -p "$ZSH_CUSTOM_DIR/plugins" "$ZSH_CUSTOM_DIR/themes"
 
  fetch_ref https://github.com/romkatv/powerlevel10k.git \
            "$ZSH_CUSTOM_DIR/themes/powerlevel10k" "$PIN_P10K"
  fetch_ref https://github.com/zsh-users/zsh-autosuggestions.git \
            "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" "$PIN_AUTOSUGGESTIONS"
  fetch_ref https://github.com/zsh-users/zsh-syntax-highlighting.git \
            "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" "$PIN_SYNTAX_HIGHLIGHTING"
  fetch_ref https://github.com/zsh-users/zsh-completions.git \
            "$ZSH_CUSTOM_DIR/plugins/zsh-completions" "$PIN_COMPLETIONS"
  fetch_ref https://github.com/Aloxaf/fzf-tab.git \
            "$ZSH_CUSTOM_DIR/plugins/fzf-tab" "$PIN_FZF_TAB"
 
  # Lectura para todos, escritura solo root
  chown -R root:root "$OMZ_DIR"
  chmod -R a+rX "$OMZ_DIR"
 
  # Pre-descarga de gitstatusd en un cache compartido. Sin esto, el PRIMER login
  # de cada usuario muestra "fetching gitstatusd..." y se queda esperando la red.
  local gs_install="${ZSH_CUSTOM_DIR}/themes/powerlevel10k/gitstatus/install"
  if [[ -x "$gs_install" ]]; then
    mkdir -p /usr/local/share/gitstatus
    if GITSTATUS_CACHE_DIR=/usr/local/share/gitstatus "$gs_install" -f >/dev/null 2>&1; then
      chmod -R a+rX /usr/local/share/gitstatus
      ok "gitstatusd pre-descargado (login instantaneo)"
    else
      warn "no pude pre-descargar gitstatusd; se bajara solo en el primer login"
    fi
  fi
}
 
# ============================== 3. Plantillas ================================
write_templates() {
  log "Escribiendo plantillas de configuracion"
  mkdir -p /usr/local/share/zsh-setup
 
  # --- .zshrc ---------------------------------------------------------------
  cat > /usr/local/share/zsh-setup/zshrc <<'ZSHRC_EOF'
# ~/.zshrc - generado por setup-zsh.sh
# OJO: si volves a correr el script, este archivo se regenera.
# Poné tus cosas en ~/.zshrc.local, que nunca se toca.
 
# --- Powerlevel10k instant prompt (tiene que ir al principio de todo) --------
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
 
# --- Oh My Zsh --------------------------------------------------------------
# gitstatusd (el motor de git de p10k) se descarga una sola vez para toda la VM
# durante el setup; asi el primer login no espera ninguna descarga.
export GITSTATUS_CACHE_DIR=/usr/local/share/gitstatus
export ZSH="/usr/local/share/oh-my-zsh"
export ZSH_CUSTOM="/usr/local/share/oh-my-zsh/custom"
ZSH_THEME="powerlevel10k/powerlevel10k"
 
# La instalacion es compartida y de solo lectura: nadie auto-actualiza.
# Para actualizar: sudo /usr/local/sbin/setup-zsh.sh --update
zstyle ':omz:update' mode disabled
DISABLE_AUTO_UPDATE="true"
 
# Cache de completions por usuario (el dir de OMZ no es escribible)
ZSH_COMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zcompdump-${HOST}-${ZSH_VERSION}"
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
 
plugins=(
  git
  sudo                    # ESC ESC = antepone sudo al ultimo comando
  command-not-found
  extract                 # 'extract archivo.tar.gz' para cualquier formato
  colored-man-pages
  docker
  docker-compose
  kubectl
  systemd
  ubuntu
  history-substring-search  # flecha arriba busca por lo que ya escribiste
  zsh-completions
  fzf-tab                   # completions con fzf (antes de autosuggestions)
  zsh-autosuggestions
  zsh-syntax-highlighting   # SIEMPRE el ultimo
)
 
source "$ZSH/oh-my-zsh.sh"
 
# --- Historial --------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt EXTENDED_HISTORY          # guarda timestamp
setopt INC_APPEND_HISTORY        # escribe al instante, no al salir
setopt SHARE_HISTORY             # historial compartido entre sesiones
setopt HIST_IGNORE_ALL_DUPS      # sin duplicados
setopt HIST_IGNORE_SPACE         # ' comando' no se guarda (util para secretos)
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY               # expande !! antes de ejecutar
 
# --- Comportamiento del shell ----------------------------------------------
setopt AUTO_CD                   # 'cd /etc' -> '/etc'
setopt AUTO_PUSHD PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS      # permite # en la linea de comandos
setopt NO_BEEP
setopt CORRECT                   # sugiere correccion de tipeo en comandos
 
# --- Teclas -----------------------------------------------------------------
bindkey -e                                   # modo emacs
if (( $+widgets[history-substring-search-up] )); then
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey '^[OA' history-substring-search-up     # variante en algunos emuladores
  bindkey '^[OB' history-substring-search-down
fi
bindkey '^[[1;5C' forward-word               # ctrl + ->
bindkey '^[[1;5D' backward-word              # ctrl + <-
bindkey '^[[3~'   delete-char
bindkey '^[[H'    beginning-of-line
bindkey '^[[F'    end-of-line
 
# --- Completions ------------------------------------------------------------
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # case-insensitive
zstyle ':completion:*' menu no                              # lo maneja fzf-tab
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -1 --color=always $realpath'
 
# --- Entorno ----------------------------------------------------------------
export EDITOR="${EDITOR:-vim}"
export VISUAL="$EDITOR"
export PAGER="${PAGER:-less}"
export LESS="-R -F -X"
export LANG="${LANG:-en_US.UTF-8}"
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
 
# --- Integraciones opcionales (solo si la herramienta existe) ---------------
if (( $+commands[fzf] )); then
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'
  (( $+commands[fd] )) && export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
  # Ubuntu 24.04+ trae 'fzf --zsh'; en versiones viejas se usan los archivos de /usr/share
  if fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
  else
    [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && source /usr/share/doc/fzf/examples/key-bindings.zsh
    [[ -f /usr/share/doc/fzf/examples/completion.zsh   ]] && source /usr/share/doc/fzf/examples/completion.zsh
  fi
fi
 
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"
 
# --- Aliases ----------------------------------------------------------------
[[ -f "$HOME/.zsh_aliases" ]] && source "$HOME/.zsh_aliases"
 
# --- Overrides locales (no versionado, gana sobre todo lo anterior) ---------
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
 
# --- Prompt -----------------------------------------------------------------
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
ZSHRC_EOF
 
  # --- .zsh_aliases ---------------------------------------------------------
  cat > /usr/local/share/zsh-setup/zsh_aliases <<'ALIAS_EOF'
# ~/.zsh_aliases - generado por setup-zsh.sh
 
# --- Listados (eza/exa si estan, si no ls) ----------------------------------
if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first'
  alias ll='eza -lg --group-directories-first --git --time-style=long-iso'
  alias la='eza -lag --group-directories-first --git --time-style=long-iso'
  alias lt='eza --tree --level=2 --group-directories-first'
elif (( $+commands[exa] )); then
  alias ls='exa --group-directories-first'
  alias ll='exa -lg --group-directories-first'
  alias la='exa -lag --group-directories-first'
  alias lt='exa --tree --level=2'
else
  alias ls='ls --color=auto --group-directories-first'
  alias ll='ls -lh --color=auto --group-directories-first'
  alias la='ls -lah --color=auto --group-directories-first'
  alias lt='tree -L 2'
fi
 
# --- Basicos ----------------------------------------------------------------
alias grep='grep --color=auto'
alias df='df -hT'
alias du='du -h'
alias free='free -h'
alias mkdir='mkdir -pv'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias c='clear'
alias h='history'
alias path='echo $PATH | tr ":" "\n"'
alias now='date +"%Y-%m-%d %H:%M:%S %Z"'
alias myip='curl -s ifconfig.me; echo'
 
# Red de seguridad: pide confirmacion antes de destruir
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
 
# Nota: a proposito NO pisamos 'cat' con bat. En una VM 'cat' se usa en pipes,
# heredocs y scripts pegados a mano, y los flags no son compatibles.
# Si igual lo queres, agregalo en ~/.zshrc.local:  alias cat='bat --paging=never'
if (( $+commands[bat] )); then
  alias b='bat --paging=never'      # ver un archivo con colores
  alias bl='bat'                    # con pager
fi
 
# --- Sistema / systemd ------------------------------------------------------
alias sc='sudo systemctl'
alias scs='systemctl status'
alias scr='sudo systemctl restart'
alias scst='sudo systemctl start'
alias scsp='sudo systemctl stop'
alias sce='sudo systemctl enable --now'
alias scf='systemctl --failed'
alias jc='sudo journalctl'
alias jcf='sudo journalctl -f'
alias jcu='sudo journalctl -u'
alias jce='sudo journalctl -p err -b'
 
# --- Paquetes ---------------------------------------------------------------
alias update='sudo apt-get update && sudo apt-get upgrade -y'
alias install='sudo apt-get install -y'
alias search='apt-cache search'
alias autoclean='sudo apt-get autoremove -y && sudo apt-get autoclean'
 
# --- Redes ------------------------------------------------------------------
alias ports='sudo ss -tulpn'
alias listen='sudo ss -tlpn'
alias conns='sudo ss -tanp'
alias ipa='ip -c -br addr'
alias ipl='ip -c -br link'
alias ipr='ip -c route'
alias ping='ping -c 5'
alias dnsflush='sudo resolvectl flush-caches'
alias dnsstat='resolvectl status'
 
# --- Docker -----------------------------------------------------------------
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"'
alias dlog='docker logs -f --tail 100'
alias dex='docker exec -it'
alias dprune='docker system prune -af --volumes'
 
# --- Kubernetes -------------------------------------------------------------
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs -f --tail=100'
alias kns='kubectl config set-context --current --namespace'
alias kctx='kubectl config use-context'
 
# --- Git (complementa el plugin git de OMZ) ---------------------------------
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate --all -20'
alias gd='git diff'
alias gp='git pull --ff-only'
 
# --- Funciones utiles -------------------------------------------------------
# mkcd <dir>: crea el directorio y entra
mkcd() { mkdir -p "$1" && cd "$1"; }
 
# backup <archivo>: copia con timestamp
backup() {
  local dst="$1.$(date +%Y%m%d-%H%M%S).bak"
  cp -a "$1" "$dst" && echo "-> $dst"
}
 
# psg <patron>: busca procesos
psg() { ps aux | grep -i "[${1:0:1}]${1:1}"; }
 
# port <numero>: quien escucha en ese puerto
port() { sudo ss -tulpn | grep -E ":$1\b"; }
 
# sysinfo: resumen rapido de la VM
sysinfo() {
  echo "Host:    $(hostname -f 2>/dev/null || hostname)"
  echo "OS:      $(. /etc/os-release && echo "$PRETTY_NAME")"
  echo "Kernel:  $(uname -r)"
  echo "Uptime:  $(uptime -p)"
  echo "CPU:     $(nproc) cores"
  echo "RAM:     $(free -h | awk '/^Mem:/{print $3" / "$2}')"
  echo "Disk /:  $(df -h / | awk 'NR==2{print $3" / "$2" ("$5")"}')"
  echo "IP:      $(hostname -I 2>/dev/null | tr ' ' '\n' | head -3 | paste -sd' ')"
}
ALIAS_EOF
 
  # --- .p10k.zsh ------------------------------------------------------------
  # Config hecha a mano (sin wizard). Detecta si la terminal banca iconos.
  cat > /usr/local/share/zsh-setup/p10k.zsh <<'P10K_EOF'
# ~/.p10k.zsh - generado por setup-zsh.sh
# Config minimalista de Powerlevel10k con deteccion automatica de iconos.
# Para reconfigurar a gusto: p10k configure  (te sobrescribe este archivo)
 
() {
  emulate -L zsh -o extended_glob
  unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'
 
  # --- Deteccion de soporte de iconos ---------------------------------------
  # Si estas en consola serie/TTY, sin UTF-8, o exportaste ZSH_ASCII_PROMPT=1,
  # cae a modo ASCII para no ver cuadraditos.
  local _icons=1
  [[ "$TERM" == (linux|dumb|vt100|vt220) ]] && _icons=0
  [[ "${LANG}${LC_ALL}${LC_CTYPE}" != *(UTF-8|utf8|UTF8)* ]] && _icons=0
  [[ -n "${ZSH_ASCII_PROMPT:-}" ]] && _icons=0
 
 
  # --- Estructura del prompt ------------------------------------------------
  typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
    context                 # user@host (solo por SSH o como root)
    dir                     # directorio actual
    vcs                     # rama de git + estado
    newline
    prompt_char             # > verde / > rojo si fallo el comando anterior
  )
  typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
    status                  # exit code cuando != 0
    command_execution_time  # duracion si tardo mas de 3s
    background_jobs
    kubecontext             # solo aparece con kubectl en uso
    aws
    virtualenv
    time
  )
 
  typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
  typeset -g POWERLEVEL9K_BACKGROUND=              # estilo "lean", sin bloques
  typeset -g POWERLEVEL9K_ICON_PADDING=none
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_{LEFT,RIGHT}_WHITESPACE=
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SUBSEGMENT_SEPARATOR=' '
  typeset -g POWERLEVEL9K_{LEFT,RIGHT}_SEGMENT_SEPARATOR=
  typeset -g POWERLEVEL9K_VISUAL_IDENTIFIER_EXPANSION='${P9K_VISUAL_IDENTIFIER}'
  typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=same-dir
  typeset -g POWERLEVEL9K_INSTANT_PROMPT=verbose
  typeset -g POWERLEVEL9K_DISABLE_HOT_RELOAD=true
 
  # --- Iconos vs ASCII (se aplica al final para pisar los defaults) ----------
  if (( _icons )); then
    typeset -g POWERLEVEL9K_MODE=nerdfont-v3
    typeset -g POWERLEVEL9K_VISUAL_IDENTIFIER_EXPANSION='${P9K_VISUAL_IDENTIFIER}'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='❯'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='❮'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='V'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIOWR_CONTENT_EXPANSION='▶'
  else
    typeset -g POWERLEVEL9K_MODE=ascii
    typeset -g POWERLEVEL9K_VISUAL_IDENTIFIER_EXPANSION=
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION='>'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION='<'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION='V'
    typeset -g POWERLEVEL9K_PROMPT_CHAR_{OK,ERROR}_VIOWR_CONTENT_EXPANSION='#'
  fi
 
  # --- prompt_char ----------------------------------------------------------
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=76
  typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_FOREGROUND=196
  typeset -g POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE=true
  # Sin simbolos de inicio/fin de linea alrededor del prompt_char
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL=''
  typeset -g POWERLEVEL9K_PROMPT_CHAR_LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL=
 
  # --- context: user@host ---------------------------------------------------
  # En una VM importa saber donde estas parado y si sos root.
  typeset -g POWERLEVEL9K_CONTEXT_ROOT_TEMPLATE='%B%F{196}%n%f%F{244}@%f%F{203}%m%f'
  typeset -g POWERLEVEL9K_CONTEXT_REMOTE_TEMPLATE='%F{180}%n%f%F{244}@%f%F{180}%m%f'
  typeset -g POWERLEVEL9K_CONTEXT_TEMPLATE='%F{244}%n@%m%f'
  # Ocultar solo si sos usuario normal en sesion local
  typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_{CONTENT,VISUAL_IDENTIFIER}_EXPANSION=
 
  # --- dir ------------------------------------------------------------------
  typeset -g POWERLEVEL9K_DIR_FOREGROUND=39
  typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique
  typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=2
  typeset -g POWERLEVEL9K_SHORTEN_DELIMITER=
  typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
  typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=103
  typeset -g POWERLEVEL9K_DIR_NOT_WRITABLE_FOREGROUND=196
 
  # --- vcs / git ------------------------------------------------------------
  typeset -g POWERLEVEL9K_VCS_CLEAN_FOREGROUND=76
  typeset -g POWERLEVEL9K_VCS_MODIFIED_FOREGROUND=178
  typeset -g POWERLEVEL9K_VCS_UNTRACKED_FOREGROUND=76
  typeset -g POWERLEVEL9K_VCS_CONFLICTED_FOREGROUND=196
  typeset -g POWERLEVEL9K_VCS_LOADING_FOREGROUND=244
  typeset -g POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY=8192   # repos gigantes: no cuelga
 
  # --- status ---------------------------------------------------------------
  typeset -g POWERLEVEL9K_STATUS_OK=false                 # no molestar cuando sale bien
  typeset -g POWERLEVEL9K_STATUS_ERROR=true
  typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=196
  typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_FOREGROUND=196
  typeset -g POWERLEVEL9K_STATUS_VERBOSE_SIGNAME=false
 
  # --- tiempo de ejecucion --------------------------------------------------
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD=3
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION=0
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FOREGROUND=101
  typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT='d h m s'
 
  # --- otros ----------------------------------------------------------------
  typeset -g POWERLEVEL9K_BACKGROUND_JOBS_FOREGROUND=37
  typeset -g POWERLEVEL9K_KUBECONTEXT_FOREGROUND=134
  typeset -g POWERLEVEL9K_KUBECONTEXT_SHOW_ON_COMMAND='kubectl|helm|kubens|kubectx|k9s|flux'
  typeset -g POWERLEVEL9K_AWS_SHOW_ON_COMMAND='aws|terraform|tf'
  typeset -g POWERLEVEL9K_AWS_FOREGROUND=208
  typeset -g POWERLEVEL9K_VIRTUALENV_FOREGROUND=37
  typeset -g POWERLEVEL9K_TIME_FOREGROUND=66
  typeset -g POWERLEVEL9K_TIME_FORMAT='%D{%H:%M:%S}'
 
  (( ! $+functions[p10k] )) || p10k reload
}
 
typeset -g POWERLEVEL9K_CONFIG_FILE=${${(%):-%x}:a}
P10K_EOF
 
  chmod 0644 /usr/local/share/zsh-setup/*
  ok "plantillas en /usr/local/share/zsh-setup/"
}
 
# ========================= 4. Aplicar a cada usuario =========================
# Copia las plantillas respetando cambios locales: si el archivo ya existe y
# difiere, se guarda un .bak y se reemplaza solo si viene de este script.
deploy_file() {
  local src="$1" dst="$2" owner="$3" group="$4"
 
  if [[ -f "$dst" ]]; then
    if cmp -s "$src" "$dst"; then
      return 0                                    # identico, nada que hacer
    fi
    if ! grep -q 'generado por setup-zsh.sh' "$dst" 2>/dev/null; then
      # Archivo propio del usuario: no lo pisamos sin respaldo
      cp -a "$dst" "${dst}.pre-zsh-setup.bak"
      warn "respaldo de $dst -> ${dst}.pre-zsh-setup.bak"
    fi
  fi
 
  install -o "$owner" -g "$group" -m 0644 "$src" "$dst"
}
 
apply_to_home() {
  local home="$1" owner="$2" group="$3" label="$4"
 
  [[ -d "$home" ]] || { warn "no existe $home, salteo $label"; return 0; }
 
  deploy_file /usr/local/share/zsh-setup/zshrc       "$home/.zshrc"       "$owner" "$group"
  deploy_file /usr/local/share/zsh-setup/zsh_aliases "$home/.zsh_aliases" "$owner" "$group"
  deploy_file /usr/local/share/zsh-setup/p10k.zsh    "$home/.p10k.zsh"    "$owner" "$group"
 
  # Cache para el instant prompt y el zcompdump
  install -d -o "$owner" -g "$group" -m 0755 "$home/.cache"
 
  # Modo ASCII forzado para toda la maquina
  if [[ $FORCE_ASCII -eq 1 ]]; then
    if [[ ! -f "$home/.zshrc.local" ]] || ! grep -q ZSH_ASCII_PROMPT "$home/.zshrc.local" 2>/dev/null; then
      echo 'export ZSH_ASCII_PROMPT=1' >> "$home/.zshrc.local"
      chown "$owner:$group" "$home/.zshrc.local"
    fi
  fi
 
  ok "config aplicada a $label"
}
 
apply_to_user() {
  local user="$1"
  local home group
  home="$(getent passwd "$user" | cut -d: -f6)"
  group="$(id -gn "$user" 2>/dev/null || echo "$user")"
 
  [[ -n "$home" ]] || { warn "usuario $user sin home, salteo"; return 0; }
 
  apply_to_home "$home" "$user" "$group" "$user ($home)"
 
  if [[ $DO_CHSH -eq 1 ]]; then
    local cur zsh_path
    cur="$(getent passwd "$user" | cut -d: -f7)"
    zsh_path="$(command -v zsh)"
    if [[ "$cur" != "$zsh_path" ]]; then
      grep -qx "$zsh_path" /etc/shells || echo "$zsh_path" >> /etc/shells
      chsh -s "$zsh_path" "$user" && ok "shell por defecto de $user -> zsh"
    fi
  fi
}
 
apply_to_skel() {
  log "Aplicando a /etc/skel (usuarios futuros)"
  install -d -m 0755 "$SKEL_DIR"
  apply_to_home "$SKEL_DIR" root root "/etc/skel"
 
  # Que 'useradd' cree usuarios con zsh por defecto
  if [[ -f /etc/default/useradd ]]; then
    local zsh_path; zsh_path="$(command -v zsh)"
    if grep -qE '^SHELL=' /etc/default/useradd; then
      sed -i "s|^SHELL=.*|SHELL=${zsh_path}|" /etc/default/useradd
    else
      echo "SHELL=${zsh_path}" >> /etc/default/useradd
    fi
    ok "useradd usara zsh por defecto"
  fi
}
 
install_self() {
  # Deja el script en el sistema para poder re-correrlo (--update, nuevos users)
  # Si se ejecuto via 'curl | bash', $0 no es un archivo y esto se saltea.
  [[ -f "$0" ]] || return 0
  [[ "$(readlink -f "$0")" == "/usr/local/sbin/setup-zsh.sh" ]] && return 0
  if install -m 0755 "$0" /usr/local/sbin/setup-zsh.sh 2>/dev/null; then
    ok "script disponible en /usr/local/sbin/setup-zsh.sh"
  fi
  return 0
}
 
# ================================== Main =====================================
main() {
  log "setup-zsh v${SETUP_VERSION} | usuarios: ${TARGET_USERS[*]}"
 
  install_packages
  install_cli_tools
  install_omz
  write_templates
 
  for u in "${TARGET_USERS[@]}"; do
    apply_to_user "$u"
  done
  apply_to_skel
  install_self
 
  echo "${SETUP_VERSION} $(date -Is)" > "$STATE_FILE"
 
  echo
  ok "Listo."
  echo
  echo "  Siguientes pasos:"
  echo "    - Abri una sesion nueva (exit + ssh de nuevo) o corre:  exec zsh"
  echo "    - Para que el prompt se vea con iconos, instala una Nerd Font"
  echo "      en la terminal DE TU MAQUINA (ej. MesloLGS NF) y seleccionala."
  echo "      https://github.com/romkatv/powerlevel10k#manual-font-installation"
  echo "    - Sin Nerd Font:  export ZSH_ASCII_PROMPT=1  en ~/.zshrc.local"
  echo "    - Personalizar el prompt a gusto:  p10k configure"
  echo "    - Tus alias/exports propios van en ~/.zshrc.local (no se pisa)"
  echo "    - Actualizar OMZ y plugins:  sudo /usr/local/sbin/setup-zsh.sh --update"
  echo
}
 
main "$@"