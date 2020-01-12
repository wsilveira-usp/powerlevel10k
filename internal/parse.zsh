typeset -gA __pb_cmd_skip=(
  '}'         ''
  '{'         ''
  '|'         ''
  '||'        ''
  '&'         ''
  '&&'        ''
  '|&'        ''
  '&!'        ''
  '&|'        ''
  ')'         ''
  '('         ''
  '()'        ''
  '!'         ''
  ';'         ''
  'if'        ''
  'fi'        ''
  'elif'      ''
  'else'      ''
  'then'      ''
  'while'     ''
  'until'     ''
  'do'        ''
  'done'      ''
  'esac'      ''
  'end'       ''
  'coproc'    ''
  'nocorrect' ''
  'noglob'    ''
  'time'      ''
  '[['        '\]\]'
  '(('        '\)\)'
  'case'      '\)|esac'
  ';;'        '\)|esac'
  ';&'        '\)|esac'
  ';|'        '\)|esac'
  'foreach'   '\(*\)'
)

typeset -gA __pb_precommand=(
  '-'         ''
  'builtin'   ''
  'command'   ''
  'exec'      '-[^a]#[a]'
  'nohup'     ''
  'setsid'    ''
  'eatmydata' ''
  'catchsegv' ''
  'pkexec'    '--user'
  'doas'      '-[^aCu]#[acU]'
  'nice'      '-[^n]#[n]|--adjustment'
  'stdbuf'    '-[^ioe]#[ioe]|--(input|output|error)'
  'sudo'      '-[^aghpuUCcrtT]#[aghpuUCcrtT]|--(close-from|group|host|prompt|role|type|other-user|command-timeout|user)'
)

typeset -gA __pb_redirect=(
  '&>'   ''
  '>'    ''
  '>&'   ''
  '<'    ''
  '<&'   ''
  '<>'   ''
  '&>|'  ''
  '>|'   ''
  '&>>'  ''
  '>>'   ''
  '>>&'  ''
  '&>>|' ''
  '>>|'  ''
  '<<<'  ''
)

typeset -gA __pb_term=(
  '|'  ''
  '||' ''
  ';'  ''
  '&'  ''
  '&&' ''
  '|&' ''
  '&!' ''
  '&|' ''
  ';;' ''
  ';&' ''
  ';|' ''
  '('  ''
  ')'  ''
  '()' ''
  '}'  ''
)

typeset -gA __pb_term_skip=(
  '('  '\)'
  ';;' '\)|esac'
  ';&' '\)|esac'
  ';|' '\)|esac'
)

# Broken:
#
#   ---------------
#   : $(x)
#   ---------------
#   : `x`
#   ---------------
#   ${x/}
#   ---------------
#   - -- x
#   ---------------
#   command -p -p x
#   ---------------
#   *
#   ---------------
#   x=$y; $x
#   ---------------
#   alias x=y; y
#   ---------------
#   x <<END
#   ; END
#   END
#   ---------------
#   Setup:
#     setopt interactive_comments
#     alias x='#'
#   Punchline:
#     x; y
#   ---------------
#
# More brokenness with non-standard options (ignore_braces, ignore_close_braces, etc.).
function _parse_buffer() {
  [[ ${2:-0} == <-> ]] || return

  local rcquotes
  [[ -o rcquotes ]] && rcquotes=(-o rcquotes)

  emulate -L zsh -o extended_glob -o no_nomatch $rcquotes

  typeset -ga _buffer_commands=()

  local -r id='(<->|[[:alpha:]_][[:IDENT:]]#)'
  local -r var="\$$id|\${$id}|\"\$$id\"|\"\${$id}\""

  local -i e ic c=${2:-'1 << 62'}
  local skip n s r state
  local -a aln alp alf v commands

  if [[ -o interactive_comments ]]; then
    ic=1
    local tokens=(${(Z+C+)1})
  else
    local tokens=(${(z)1})
  fi

  {
    while (( $#tokens )); do
      (( e = $#state ))

      if (( $#alp && $#tokens == alp[-1] )); then
        aln[-1]=()
        alp[-1]=()
        if (( $#tokens == alf[-1] )); then
          alf[-1]=()
          (( e = 0 ))
        fi
      fi

      while (( c-- > 0 )) || return; do
        token=$tokens[1]
        tokens[1]=()
        if (( $+galiases[$token] )); then
          (( $aln[(eI)p$token] )) && break
          s=$galiases[$token]
          n=p$token
        elif (( e )); then
          break
        elif (( $+aliases[$token] )); then
          (( $aln[(eI)p$token] )) && break
          s=$aliases[$token]
          n=p$token
        elif [[ $token == ?*.?* ]] && (( $+saliases[${token##*.}] )); then
          r=${token##*.}
          (( $aln[(eI)s$r] )) && break
          s=${saliases[$r]%% #}
          n=s$r
        else
          break
        fi
        aln+=$n
        alp+=$#tokens
        [[ $s == *' ' ]] && alf+=$#tokens
        (( ic )) && tokens[1,0]=(${(Z+C+)s}) || tokens[1,0]=(${(z)s})
      done

      if [[ $token == '<<'(|-) ]]; then
        state=h
        continue
      fi

      case $state in
        a)
          if [[ $token == $skip ]]; then
            if [[ $token == '{' ]]; then
              _buffer_commands+=($commands)
              commands=()
              state=
            else
              skip='{'
            fi
            continue
          else
            state=t
          fi
          ;&  # fall through
        t|p*)
          if (( $+__pb_term[$token] )); then
            if [[ $token == '()' ]]; then
              state=
            else
              _buffer_commands+=($commands)
              if [[ $token == '}' ]]; then
                state=a
                skip=always
              else
                skip=$__pb_term_skip[$token]
                state=${skip:+s}
              fi
            fi
            commands=()
            continue
          elif [[ $state == t ]]; then
            continue
          fi
          ;;
        s)
          if [[ $token == $~skip ]]; then
            state=
          fi
          continue
          ;;
        *r)
          state[1]=
          continue
          ;;
        h)
          while (( $#tokens )); do
            (( e = ${tokens[(i)$token]} ))
            if [[ $tokens[e-1] == ';' && $tokens[e+1] == ';' ]]; then
              tokens[1,e]=()
              break
            else
              tokens[1,e]=()
            fi
          done
          while (( $#alp && alp[-1] >= $#tokens )); do
            aln[-1]=()
            alp[-1]=()
          done
          state=t
          continue
          ;;
      esac

      if (( $+__pb_redirect[${token#<0-255>}] )); then
        state+=r
        continue
      fi

      if [[ $token == *'$'* ]]; then
        if [[ $token == $~var ]]; then
          n=${${token##[^[:IDENT:]]}%%[^[:IDENT:]]}
          [[ $token == *'"' ]] && v=("${(P)n}") || v=(${(P)n})
          tokens[1,0]=(${(qq)v})
          continue
        fi
      fi

      case $state in
        '')
          if (( $+__pb_cmd_skip[$token] )); then
            skip=$__pb_cmd_skip[$token]
            state=${skip:+s}
            continue
          fi
          if [[ $token == *=* ]]; then
            v=${(S)token/#(<->|([[:alpha:]_][[:IDENT:]]#(|'['*[^\\](\\\\)#']')))(|'+')=}
            if (( $#v < $#token )); then
              if [[ $v == '(' ]]; then
                state=s
                skip='\)'
              fi
              continue
            fi
          fi
          : ${token::=${(Q)${~token}}}
          ;;
        p)
          : ${token::=${(Q)${~token}}}
          case $token in
            [^-]*)                    ;;
            --)     state=p1; continue;;
            $~skip) state=p2; continue;;
            *)                continue;;
          esac
          ;;
        p2)
          state=p
          continue
          ;;
      esac

      commands+=$token
      if (( $+__pb_precommand[$commands[-1]] )); then
        state=p
        skip=$__pb_precommand[$commands[-1]]
      else
        state=t
      fi
    done
  } always {
    _buffer_commands+=($commands)
    _buffer_commands=(${(u)_buffer_commands:#('(('*'))'|'`'*'`'|'$'*)})
  }
}
