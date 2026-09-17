# bash-completion для dcpmgmt.
#
# Встановлення (одне з):
#   sudo install -m 644 tools/dcpmgmt-completion.bash /etc/bash_completion.d/dcpmgmt
#   install -Dm 644 tools/dcpmgmt-completion.bash \
#       ~/.local/share/bash-completion/completions/dcpmgmt
#
# Імена доменів беруться з `dcpmgmt list --names` — тією ж копією
# інструмента, яку ви набрали в рядку. Тобто працює лише в каталозі
# інсталяції, де є dcp.conf і domains/; деінде просто нічого не підкаже.

_dcpmgmt_domains() {
    local exe="${1:-dcpmgmt}"
    "$exe" list --names 2>/dev/null
}

_dcpmgmt() {
    local -a w=("${COMP_WORDS[@]}")
    local ci=$COMP_CWORD

    # `sudo ./dcpmgmt …` — пакет bash-completion зазвичай зсуває слова сам,
    # але покладатися на це не варто: без нього COMP_WORDS[0] буде "sudo".
    while [ ${#w[@]} -gt 1 ] && [ "${w[0]}" = sudo ]; do
        w=("${w[@]:1}"); ci=$((ci - 1))
    done
    while [ ${#w[@]} -gt 1 ] && [[ "${w[0]}" == -* ]]; do
        w=("${w[@]:1}"); ci=$((ci - 1))
    done
    [ "$ci" -ge 0 ] || return 0

    local exe="${w[0]}" cmd="${w[1]:-}" cur="${w[ci]:-}" prev="${w[ci-1]:-}"
    local domains

    if [ "$ci" -le 1 ]; then
        COMPREPLY=($(compgen -W "init import add remove list doctor render apply \
                                 up down restart cert secrets version help" -- "$cur"))
        return 0
    fi

    case "$cmd" in
        add)
            if [ "$ci" -eq 2 ]; then
                COMPREPLY=($(compgen -W "wordpress redirect proxy" -- "$cur"))
            elif [ "$prev" = --to ]; then
                # Ціль редіректу — як правило, домен, який уже є в реєстрі.
                COMPREPLY=($(compgen -W "$(_dcpmgmt_domains "$exe")" -- "$cur"))
            elif [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "--image --to --upstream --no-http3 \
                                         --no-cert --staging" -- "$cur"))
            fi
            ;;
        remove|rm)
            domains="$(_dcpmgmt_domains "$exe")"
            COMPREPLY=($(compgen -W "$domains --purge" -- "$cur"))
            ;;
        up|down|restart)
            COMPREPLY=($(compgen -W "$(_dcpmgmt_domains "$exe")" -- "$cur"))
            ;;
        render)
            domains="$(_dcpmgmt_domains "$exe")"
            COMPREPLY=($(compgen -W "$domains --diff --force" -- "$cur"))
            ;;
        apply)
            COMPREPLY=($(compgen -W "--force --yes" -- "$cur"))
            ;;
        list|ls)
            if [ "$prev" = --type ]; then
                COMPREPLY=($(compgen -W "wordpress redirect proxy" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "--type --names" -- "$cur"))
            fi
            ;;
        cert)
            if [ "$ci" -eq 2 ]; then
                COMPREPLY=($(compgen -W "issue renew list" -- "$cur"))
            else
                domains="$(_dcpmgmt_domains "$exe")"
                COMPREPLY=($(compgen -W "$domains --staging --force --dry-run" -- "$cur"))
            fi
            ;;
        secrets)
            if [ "$ci" -eq 2 ]; then
                COMPREPLY=($(compgen -W "show restore key" -- "$cur"))
            elif [ "${w[2]:-}" = show ]; then
                COMPREPLY=($(compgen -W "$(_dcpmgmt_domains "$exe")" -- "$cur"))
            fi
            ;;
        import)
            if [ "$prev" = --from ]; then
                COMPREPLY=($(compgen -d -- "$cur"))
            else
                COMPREPLY=($(compgen -W "--from" -- "$cur"))
            fi
            ;;
    esac
    return 0
}

# Інструмент запускають і як `dcpmgmt`, і як `./dcpmgmt` — реєструємо обидва.
complete -F _dcpmgmt dcpmgmt ./dcpmgmt
