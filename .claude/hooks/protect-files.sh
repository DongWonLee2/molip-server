#!/usr/bin/env bash
# PreToolUse 훅: 모델의 판단과 상관없이 보호 파일 수정과 되돌릴 수 없는 명령을 막는다.
# 막을 때는 exit 2로 끝내고, stderr 메시지가 Claude에게 차단 이유로 전달된다.
# 막지 않을 때는 exit 0으로 끝내서 평소 권한 흐름(settings.json의 allow/ask/deny)에 맡긴다.

set -uo pipefail

input="$(cat)"
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
project_dir="${project_dir%/}"

block() {
  echo "protect-files: $1" >&2
  exit 2
}

# JSON 파서: jq가 있으면 jq, 없으면 python3. 둘 다 없으면 안전하게 막는다.
if command -v jq >/dev/null 2>&1; then
  json_get() { printf '%s' "$input" | jq -r "$1 // empty"; }
elif command -v python3 >/dev/null 2>&1; then
  json_get() {
    printf '%s' "$input" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for key in sys.argv[1].lstrip(".").split("."):
    d = d.get(key) if isinstance(d, dict) else None
print("" if d is None else d)
' "$1"
  }
else
  block "훅이 입력을 읽으려면 jq 또는 python3이 필요합니다. 'brew install jq'로 설치한 뒤 다시 시도하세요."
fi

tool="$(json_get .tool_name)"

# 절대 경로를 프로젝트 기준 상대 경로로 바꾼다.
to_relative() {
  local p="$1"
  case "$p" in
    "$project_dir"/*) p="${p#"$project_dir"/}" ;;
  esac
  printf '%s' "${p#./}"
}

check_file() {
  local path="$1"
  local base="${path##*/}"

  case "$base" in
    .env.example|.env.sample) return 0 ;;
    .env|.env.*)
      block "$path 는 비밀 값 파일이라 수정할 수 없습니다. 새 키가 필요하면 이름만 .env.example에 추가하고 사용자에게 값을 넣어 달라고 요청하세요." ;;
    *.pem|*.key|*.p12|*.jks)
      block "$path 는 키 파일이라 수정할 수 없습니다." ;;
  esac

  case "$path" in
    src/main/resources/application-prod.yml|src/main/resources/application-prod.yaml)
      block "$path 는 운영 설정이라 사람이 직접 수정합니다. 바꿀 내용을 diff로 제안만 하세요." ;;
    .claude/settings.json|.claude/hooks/*)
      block "$path 는 하네스 설정이라 사람이 직접 수정합니다. 필요한 변경을 제안만 하세요." ;;
    src/main/resources/db/migration/*)
      # 이미 커밋된 마이그레이션은 어딘가에 적용됐다고 보고 막는다. 새로 만드는 파일은 허용한다.
      if git -C "$project_dir" ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
        block "$path 는 이미 커밋된 Flyway 마이그레이션이라 수정할 수 없습니다. 다음 버전 번호로 새 파일(V{n}__설명.sql)을 추가하세요."
      fi ;;
  esac
}

check_command() {
  local cmd="$1"

  # 강제 푸시 (--force-with-lease는 허용)
  if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push([[:space:]].*)?[[:space:]](--force|-f)([[:space:]]|$)'; then
    block "강제 푸시는 막혀 있습니다. 필요하면 사용자가 직접 실행합니다."
  fi

  # DB와 데이터를 지우는 명령
  if printf '%s' "$cmd" | grep -Eiq 'flywayClean|flyway[[:space:]]+clean|drop[[:space:]]+(database|schema)'; then
    block "DB 전체를 지우는 명령은 막혀 있습니다."
  fi
  if printf '%s' "$cmd" | grep -Eq 'docker([[:space:]]+compose|-compose)[[:space:]]+down([[:space:]].*)?[[:space:]](-v|--volumes)([[:space:]]|$)|docker[[:space:]]+volume[[:space:]]+(rm|prune)|docker[[:space:]]+system[[:space:]]+prune'; then
    block "Docker 볼륨을 지우는 명령은 로컬 DB 데이터를 날리므로 막혀 있습니다. 필요하면 사용자가 직접 실행합니다."
  fi

  # 루트, 홈, 프로젝트 전체 삭제
  if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f?[a-zA-Z]*[[:space:]]+(/|~|\$HOME|\.|\*|\./\*)([[:space:]]|$)'; then
    block "광범위한 삭제 명령은 막혀 있습니다. 지울 경로를 구체적으로 지정하세요."
  fi

  # 셸로 보호 파일을 읽거나 쓰기 (.env.example은 제외)
  local stripped
  stripped="$(printf '%s' "$cmd" | sed -E 's/\.env\.(example|sample)//g')"
  if printf '%s' "$stripped" | grep -Eq '(^|[^A-Za-z0-9_])\.env(\.[A-Za-z]+)?([^A-Za-z0-9_.]|$)'; then
    if printf '%s' "$stripped" | grep -Eq '(^|[;&|[:space:]])(cat|less|more|head|tail|bat|nano|vi|vim|tee|cp|mv|rm|truncate)[[:space:]]|>|sed[[:space:]]+-i|perl[[:space:]]+-i'; then
      block "셸로 .env 파일을 읽거나 바꿀 수 없습니다. 필요한 값은 사용자에게 요청하세요."
    fi
  fi
  if printf '%s' "$stripped" | grep -Eq 'application-prod\.ya?ml' && printf '%s' "$stripped" | grep -Eq '>|sed[[:space:]]+-i|perl[[:space:]]+-i|(^|[[:space:]])(tee|cp|mv|rm|truncate)[[:space:]]'; then
    block "셸로 운영 설정을 바꿀 수 없습니다."
  fi
  if printf '%s' "$stripped" | grep -Eq '\.claude/(settings\.json|hooks/)' && printf '%s' "$stripped" | grep -Eq '>|sed[[:space:]]+-i|perl[[:space:]]+-i|chmod|(^|[[:space:]])(tee|cp|mv|rm|truncate)[[:space:]]'; then
    block "셸로 하네스 설정을 바꿀 수 없습니다."
  fi
}

case "$tool" in
  Edit|MultiEdit|Write|NotebookEdit)
    file_path="$(json_get .tool_input.file_path)"
    [ -z "$file_path" ] && file_path="$(json_get .tool_input.notebook_path)"
    [ -n "$file_path" ] && check_file "$(to_relative "$file_path")"
    ;;
  Bash)
    command_text="$(json_get .tool_input.command)"
    [ -n "$command_text" ] && check_command "$command_text"
    ;;
esac

exit 0
