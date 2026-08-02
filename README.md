# setup-zsh.sh — zsh listo para VMs Ubuntu

Un solo script, idempotente, que deja zsh configurado en una VM Ubuntu recién
deployada: Oh My Zsh + Powerlevel10k + plugins esenciales + herramientas CLI
modernas, aplicado al usuario, a `root` y a `/etc/skel` (para todo usuario futuro).

Sin dependencias más allá de `apt` y `git`. Todas las versiones que instala
están **pineadas**, así que dos VMs deployadas con semanas de diferencia quedan
idénticas.

---

## TL;DR

```bash
curl -fsSLO https://raw.githubusercontent.com/darks00ul/setup-zsh/main/setup-zsh.sh
less setup-zsh.sh          # miralo antes: lo vas a correr como root
sudo bash setup-zsh.sh
exec zsh
```

Si preferís no traer nada por red:

```bash
scp setup-zsh.sh usuario@vm:/tmp/ && ssh usuario@vm 'sudo bash /tmp/setup-zsh.sh'
```

> **Sobre el `curl | sudo bash` de una línea:** funciona, pero no está en el
> TL;DR a propósito. Es un script que corre como root en tu server; bajalo,
> leelo una vez, y después automatizalo con confianza.

---

## Qué cambia en tu sistema

Leé esto antes de correrlo en un server que no sea tuyo. Nada es destructivo y
todo es idempotente — se puede correr N veces sin romper nada — pero son
cambios a nivel sistema:

- Instala paquetes con `apt`: `zsh`, `git`, `curl` y las herramientas CLI opcionales.
- Clona Oh My Zsh + 5 plugins en `/usr/local/share/oh-my-zsh` (compartido, solo lectura).
- Escribe `~/.zshrc`, `~/.zsh_aliases` y `~/.p10k.zsh` en cada usuario objetivo.
  Si ya tenías un `~/.zshrc` propio, lo respalda como `~/.zshrc.pre-zsh-setup.bak`.
- **Cambia el shell por defecto** de esos usuarios y de `root` a zsh (`--no-chsh` lo evita).
- Escribe en `/etc/skel`, así todo usuario futuro hereda esta config.
- Ajusta `SHELL=` en `/etc/default/useradd` para que `useradd` cree usuarios con zsh.
- Se copia a `/usr/local/sbin/setup-zsh.sh` para poder re-correrlo después.

Probado en Ubuntu 24.04. Compatible con 20.04 / 22.04: los paquetes que no
existan en esa versión se saltean y los aliases caen al fallback.

---

## Flags

| Flag | Qué hace |
|---|---|
| *(sin flags)* | usuario que invocó `sudo` + `root` + `/etc/skel` |
| `--user NOMBRE` | un usuario puntual (repetible: `--user a --user b`) |
| `--all-users` | todos los usuarios con UID ≥ 1000 |
| `--no-tools` | solo zsh, sin `fzf`/`bat`/`eza`/etc. |
| `--no-chsh` | no cambia el shell por defecto de nadie |
| `--ascii` | fuerza prompt ASCII en toda la VM (sin Nerd Font) |
| `--update` | re-sincroniza Oh My Zsh y plugins a las versiones pineadas |
| `--update --latest` | actualiza al `HEAD` de cada repo, ignorando los pines |
| `--help` | ayuda |

---

## Versiones pineadas

El script instala **exactamente** estas versiones, no el `HEAD` de cada repo:

| Proyecto | Versión |
|---|---|
| [ohmyzsh/ohmyzsh](https://github.com/ohmyzsh/ohmyzsh) | `c5ba74cf` (master @ 2026-07-30) |
| [romkatv/powerlevel10k](https://github.com/romkatv/powerlevel10k) | `v1.20.0` |
| [zsh-users/zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | `v0.7.1` |
| [zsh-users/zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | `0.8.0` |
| [zsh-users/zsh-completions](https://github.com/zsh-users/zsh-completions) | `0.36.0` |
| [Aloxaf/fzf-tab](https://github.com/Aloxaf/fzf-tab) | `v1.3.0` |

**Por qué importa.** El script instala software de terceros como root. Sin
pinear, cada deploy trae lo que haya en `master` ese día: la VM de hoy no es
igual a la de la semana pasada, y si a alguno de esos repos le comprometen la
cuenta, eso entra a tu flota sin que nadie lo apruebe. Con los pines, subir de
versión es un commit revisable.

**Para actualizar:** mirá los releases del repo, cambiá el tag en la sección
`Versiones pineadas` al principio del script, commiteá, y corré
`sudo setup-zsh.sh --update` en las VMs.

**Para probar upstream sin pinear:** `sudo setup-zsh.sh --update --latest`.
Volvés atrás con `sudo setup-zsh.sh --update` — el rollback a la versión
pineada funciona.

---

## Qué instala y dónde

| Qué | Dónde |
|---|---|
| Oh My Zsh (compartido, solo lectura) | `/usr/local/share/oh-my-zsh` |
| Powerlevel10k + plugins externos | `/usr/local/share/oh-my-zsh/custom` |
| `gitstatusd` pre-descargado | `/usr/local/share/gitstatus` |
| Plantillas de config | `/usr/local/share/zsh-setup/` |
| Copia del script | `/usr/local/sbin/setup-zsh.sh` |
| Config por usuario | `~/.zshrc`, `~/.zsh_aliases`, `~/.p10k.zsh` |
| Tus cosas (nunca se pisa) | `~/.zshrc.local` |

**Una sola copia de Oh My Zsh para toda la VM.** No se clona por usuario, así
que 10 usuarios no son 10 clones de ~50 MB, y actualizás una vez para todos.

**`gitstatusd` viene pre-descargado.** Sin esto, el primer login de cada
usuario se queda esperando `[powerlevel10k] fetching gitstatusd...` — molesto en
una VM recién deployada, y directamente colgado si la VM no tiene salida a
GitHub.

### Plugins

`git` · `sudo` (ESC ESC antepone sudo) · `command-not-found` · `extract` ·
`colored-man-pages` · `docker` · `docker-compose` · `kubectl` · `systemd` ·
`ubuntu` · `history-substring-search` · `zsh-completions` · `fzf-tab` ·
`zsh-autosuggestions` · `zsh-syntax-highlighting`

### Herramientas CLI

`fzf` · `bat` · `ripgrep` · `fd` · `eza` · `zoxide` · `tree` · `jq` · `htop` ·
`ncdu` · `unzip`

Ubuntu renombra dos binarios por conflicto de nombres (`batcat`, `fdfind`); el
script crea los symlinks `bat` y `fd` en `/usr/local/bin`.

---

## El prompt

Powerlevel10k en estilo *lean* (sin bloques de colores), dos líneas:

```
root@vm  ~/proyectos/infra   main                    1 ↵  4s  12:34:56
❯
```

Muestra `user@host` solo si sos root o entraste por SSH, la rama de git con
color según el estado, el exit code cuando falla algo, cuánto tardó el último
comando si pasó de 3s, y el contexto de kubectl/aws solo cuando estás usando
esos comandos.

### Nerd Font

Para ver los iconos, instalá una Nerd Font **en la terminal de tu máquina**
(no en la VM) — la recomendada es
[MesloLGS NF](https://github.com/romkatv/powerlevel10k#manual-font-installation).

**Si no querés o no podés**, el prompt detecta solo cuándo caer a ASCII
(consola serie, `TERM=linux`, locale sin UTF-8). Para forzarlo:

```bash
echo 'export ZSH_ASCII_PROMPT=1' >> ~/.zshrc.local   # un usuario
sudo setup-zsh.sh --ascii                            # toda la VM
```

Para rediseñar el prompt a gusto con el wizard: `p10k configure` (te reescribe
`~/.p10k.zsh`; el script respeta ese archivo mientras no lo vuelvas a correr).

---

## Personalizar

Todo lo tuyo va en **`~/.zshrc.local`** — se carga al final y nunca lo pisa el
script:

```bash
export EDITOR=nano
alias deploy='ansible-playbook site.yml'
unsetopt CORRECT        # si te molesta la corrección de tipeos
alias cat='bat --paging=never'
```

Si querés cambiar los defaults para toda la flota, editá el script y
redeployalo — es la fuente de verdad.

---

## Aliases y funciones incluidos

Están todos en `~/.zsh_aliases`, agrupados por tema. Los más usados:

**systemd** — `sc` (systemctl) · `scs` (status) · `scr` (restart) ·
`scf` (failed) · `jcu` (journalctl -u) · `jcf` (journalctl -f) · `jce` (errores del boot)

**Redes** — `ports` / `listen` (ss) · `ipa` / `ipl` / `ipr` (ip -c -br) ·
`port 443` (quién escucha ahí) · `myip` · `dnsstat`

**Docker** — `d` · `dc` · `dps` · `dlog` · `dex` · `dprune`

**Kubernetes** — `k` · `kg` · `kd` · `kl` · `kns` · `kctx`

**Funciones** — `mkcd dir` · `backup archivo` · `psg patron` · `port 8080` ·
`sysinfo` (resumen de la VM: OS, kernel, uptime, CPU, RAM, disco, IPs)

`rm` / `cp` / `mv` van con `-i` por defecto. Si te estorba, `\rm` salta el alias.

`cat` **no** está pisado con `bat` a propósito: en una VM `cat` se usa en pipes
y heredocs y los flags no son compatibles. Tenés `b` y `bl` para eso.

---

## Cloud-init (opcional)

Si querés que se aplique solo al deployar, hospedá el script en algún lado
alcanzable desde la VM y usá:

```yaml
#cloud-config
package_update: true
runcmd:
  - [ sh, -c, "curl -fsSL https://tu-servidor/setup-zsh.sh -o /tmp/setup-zsh.sh" ]
  - [ bash, /tmp/setup-zsh.sh ]
```

O si preferís no depender de un servidor, embebelo:

```yaml
#cloud-config
write_files:
  - path: /opt/setup-zsh.sh
    permissions: '0755'
    encoding: b64
    content: |
      <salida de: base64 -w0 setup-zsh.sh>
runcmd:
  - [ /opt/setup-zsh.sh ]
```

Cloud-init corre como root, así que no hace falta `sudo`. `--all-users` no
sirve ahí (todavía no existe ningún usuario); `/etc/skel` se encarga de los que
cree cloud-init después.

---

## Requisitos

- Ubuntu/Debian con `apt-get`
- root o sudo
- Salida a internet (GitHub para los repos, el mirror de apt para los paquetes)

---

## Créditos

Este script no reinventa nada: instala y configura el trabajo de otros.

- [Oh My Zsh](https://github.com/ohmyzsh/ohmyzsh) — MIT
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k) — MIT
- [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) — MIT
- [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) — BSD-3-Clause
- [zsh-completions](https://github.com/zsh-users/zsh-completions) — MIT
- [fzf-tab](https://github.com/Aloxaf/fzf-tab) — MIT

Se clonan en tiempo de ejecución; este repo no redistribuye código de terceros.

## Licencia

MIT — ver [LICENSE](LICENSE).
