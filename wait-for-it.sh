#!/bin/sh
# wait-for-it.sh: wait for a host and port to be available (safer variant)
#
# - Validates numeric inputs for TIMEOUT and PORT
# - Avoids command substitution with untrusted variables (no $(seq $TIMEOUT))
# - Uses exec "$@" to run the child command preserving arguments safely
# - Checks that 'nc' is available

TIMEOUT=15
QUIET=0
STRICT=0
HOST=
PORT=
CHILD_PRESENT=0

usage() {
  cat << USAGE >&2
Usage:
  $0 host:port [-s] [-t timeout] [-- command args]
  -h HOST | --host=HOST       Host or IP under test
  -p PORT | --port=PORT       TCP port under test
                                Alternatively, you specify the host and port as host:port
  -s | --strict               Only execute subcommand if the test succeeds
  -q | --quiet                Don't output any status messages
  -t TIMEOUT | --timeout=TIMEOUT
                              Timeout in seconds, zero for no timeout (default 15)
  -- COMMAND ARGS             Execute command with args after the test finishes
USAGE
  exit 1
}

is_positive_integer_or_zero() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

wait_for() {
  if [ "$QUIET" -eq 0 ]; then
    echo "Waiting for $HOST:$PORT..."
  fi

  # Check for nc
  if ! command -v nc >/dev/null 2>&1; then
    echo "Error: 'nc' (netcat) is required but was not found in PATH" >&2
    return 2
  fi

  if [ "$TIMEOUT" -eq 0 ]; then
    # no timeout: loop until success
    seconds=0
    while true; do
      if nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
        if [ "$QUIET" -eq 0 ]; then
          echo "$HOST:$PORT is available after $seconds seconds"
        fi
        return 0
      fi
      seconds=$((seconds + 1))
      sleep 1
    done
  else
    seconds=0
    while [ "$seconds" -lt "$TIMEOUT" ]; do
      if nc -z "$HOST" "$PORT" >/dev/null 2>&1; then
        if [ "$QUIET" -eq 0 ]; then
          echo "$HOST:$PORT is available after $seconds seconds"
        fi
        return 0
      fi
      seconds=$((seconds + 1))
      sleep 1
    done
    echo "Timeout occurred after waiting $TIMEOUT seconds for $HOST:$PORT"
    return 1
  fi
}

# process arguments
while [ $# -gt 0 ]; do
  case "$1" in
    *:* )
      HOST=$(printf "%s\n" "$1" | cut -d : -f 1)
      PORT=$(printf "%s\n" "$1" | cut -d : -f 2)
      shift 1
      ;;
    -h | --host)
      HOST="$2"
      if [ "$HOST" = "" ]; then break; fi
      shift 2
      ;;
    --host=*)
      HOST="${1#*=}"
      shift 1
      ;;
    -p | --port)
      PORT="$2"
      if [ "$PORT" = "" ]; then break; fi
      shift 2
      ;;
    --port=*)
      PORT="${1#*=}"
      shift 1
      ;;
    -t | --timeout)
      TIMEOUT="$2"
      if [ "$TIMEOUT" = "" ]; then break; fi
      shift 2
      ;;
    --timeout=*)
      TIMEOUT="${1#*=}"
      shift 1
      ;;
    -s | --strict)
      STRICT=1
      shift 1
      ;;
    -q | --quiet)
      QUIET=1
      shift 1
      ;;
    --)
      # The rest are child command args; keep them as positional parameters
      shift
      CHILD_PRESENT=1
      break
      ;;
    -*)
      echo "Unknown argument: $1"
      usage
      ;;
    *)
      # start of the child command; keep as positional parameters
      CHILD_PRESENT=1
      break
      ;;
  esac
done

if [ -z "$HOST" ] || [ -z "$PORT" ]; then
  echo "Error: you need to provide a host and port to test."
  usage
fi

# Validate timeout and port
if ! is_positive_integer_or_zero "$TIMEOUT"; then
  echo "Error: timeout must be a non-negative integer: got '$TIMEOUT'" >&2
  exit 2
fi

case "$PORT" in
  ''|*[!0-9]*)
    echo "Error: port must be a number: got '$PORT'" >&2
    exit 2
    ;;
esac

wait_for
RESULT=$?

if [ "$CHILD_PRESENT" -eq 1 ]; then
  if [ $RESULT -ne 0 ] && [ "$STRICT" -eq 1 ]; then
    echo "Strict mode: command will not be executed due to timeout."
    exit $RESULT
  fi
  # Exec the child command preserving positional arguments and correct quoting
  exec "$@"
else
  exit $RESULT
fi
