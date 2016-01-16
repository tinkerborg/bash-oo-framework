#!/usr/bin/env bash

#__INTERNAL_LOGGING__=true
source "$( cd "${BASH_SOURCE[0]%/*}" && pwd )/../lib/oo-framework.sh"

namespace seamless

Log.AddOutput seamless CUSTOM
Log.AddOutput error ERROR
#Log.AddOutput oo/parameters-executing CUSTOM

# ------------------------ #

declare __declaration_type

getDeclaration() {
  local variableName="$1"
  local targetVariable="$2"
  
  local declaration
  local regexArray="declare -([a-zA-Z-]+) $variableName='(.*)'"
  local regex="declare -([a-zA-Z-]+) $variableName=\"(.*)\""
  local definition=$(declare -p $variableName)
  
  local escaped="'\\\'"
  local escapedQuotes='\\"'
  local singleQuote='"'
  
  if [[ "$definition" =~ $regexArray ]]
  then
    declaration="${BASH_REMATCH[2]//$escaped/}"
  elif [[ "$definition" =~ $regex ]]
  then
    declaration="${BASH_REMATCH[2]//$escaped/}"
    declaration="${declaration//$escapedQuotes/$singleQuote}"
  fi
  
  eval $targetVariable=\$declaration
  eval ${targetVariable}_type=\${BASH_REMATCH[1]}
  # __declaration_type=${BASH_REMATCH[1]}
}

printDeclaration() {
  local __declaration
  getDeclaration "$1" __declaration
  echo "$__declaration"
}

capturePipe() {
  read -r -d '' $1
}

capturePipeFaithful() {
  IFS= read -r -d '' $1
}

## note: declaration needs to be trimmed, 
## since bash adds an enter at the end, hence %?
alias @resolveThis="
  if [[ -z \${__use_this_natively+x} ]];
  then
    local __declaration;
    local __declaration_type;
    
    if [[ ! -z \${returnValueDefinition+x} ]];
    then
      __declaration=\"\$returnValueDefinition\"
      __declaration_type=\$returnValueType
    elif [[ -z \${thisReference+x} ]]; 
    then
      capturePipe __declaration;
    else
      getDeclaration \$thisReference __declaration;
      # local __mutableName=\$thisReference;
      unset thisReference;
    fi;
    local -\${__declaration_type:--} this=\${__declaration};
    unset __declaration;
    unset __declaration_type;
  fi"

# there could be a variable "modifiedThis", 
# which is set to "printDeclaration this"
# so we kind of have two returns, one real one, 
# and one for the internal change
#
# this way:
# someMap set a 30
#
# would actually update someMap
# and manual rewriting: someMap=$(someMap set a 30)
# would not be required 

@return() {
  local variableName=$1
  
  local __return_declaration
  local __return_declaration_type
  
  ## if not returning anything, just update the self
  if [[ ! -z "$variableName" ]]
  then
    getDeclaration $variableName __return_declaration
  elif [[ ! -z "${monad+x}" ]]
  then
    getDeclaration this __return_declaration
  fi
  
  if [[ ! -z ${__return_self_and_result+x} ]]
  then
    local -a __return=("$(printDeclaration this)" "$__return_declaration" "$__return_declaration_type")
    
    printDeclaration __return
    # __modifiedThis="$(printDeclaration this)"
  else
    echo "$__return_declaration"
  fi
}
alias @get='printDeclaration'

# ------------------------ #

executeForType() {
  local type="$1"
  local variableName="$2"
  local method="$3"
  
  shift; shift; shift;
  
  # local __modifiedThis
  
  thisReference=$variableName $type.$method "$@"
  
  # if [ ! -z ${__modifiedThis+x} ]
  # then
    # eval $variableName=\$__modifiedThis
  # fi
# thisReference=result $type.$
}

# /**
#  * used inside handleType() for getting out the return value and updating this 
#  */
executeStack() {
  DEBUG Log "will execute: $method (${params[@]})"
  
  # get result (0=this, 1=return_value)
  # eval "result=\$(executeForType \"\$type\" \"\$variableName\" \"\$method\" \"\${params[@]}\")"
  # result=$(executeForType "$type" "$variableName" "$method" "${params[@]}")
  
  local -a result=$(executeForType "$type" "$variableName" "$method" "${params[@]}")
  
  # declare -p result
  local assignResult="${result[0]}"
  # declare -p assignResult
  
  # update the object
  eval "$variableName=$assignResult"
  
  # TODO: this should work directly but doesn't
  # eval $variableName=\$assignResult
  
  # update the result
  returnValueDefinition="${result[1]}"
  returnValueType="${result[2]}"
  
  # TODO: act on the returnValue, not on the base
}

handleType() {
  local variableName=$1
  local type=$(Variable.GetType $variableName)
  
  if [[ "$type" == "undefined" ]]
  then
    e="No variable named: $variableName" throw
    return
  fi
  
  shift
  
  local returnValueDefinition
  local returnValueType
  
  local __return_self_and_result=true
  
  if [[ $# -gt 0 ]]
  then
    local method
    local -a params
    local mode=method
    local prevMode
    local prevModeTemp
    while [[ $# -gt 0 ]]
    do
      prevModeTemp=$mode
      if [[ "$1" == '[' || "$1" == '{' ]]
      then
        mode=params
      elif [[ "$1" == '[]' || "$1" == ']' || "$1" == '{}' || "$1" == '}' ]]
      then
        executeStack
        
        method=''
        params=()
        mode=method
        prevModeTemp=params
      elif [[ "$mode" == 'params' ]]
      then
        params+=("$1")
      elif [[ "$mode" == 'method' ]]
      then
        if [[ "$prevMode" == 'method' ]]
        then
          executeStack
        fi
        method="$1"
      fi
      prevMode=$prevModeTemp
      shift
    done
    
    if [[ "$mode" == 'method' && "${#method}" -gt 0 ]]
    then
      executeStack
    fi
    
    # finally echo the latest return value if not empty
    if [[ ! -z "$returnValueDefinition" ]]
    then
      echo "$returnValueDefinition"
    fi
  else
    @get $variableName
  fi
}

Variable.GetType() {
	local typeInfo="$(declare -p $1 2> /dev/null || declare -p | grep "^declare -[aAign\-]* $1\(=\|$\)" || true)"

	if [[ -z "$typeInfo" ]]
	then
		echo undefined
		return 0
	fi

	if [[ "$typeInfo" == "declare -n"* ]]
	then
		echo reference
	elif [[ "$typeInfo" == "declare -a"* ]]
	then
		echo array
	elif [[ "$typeInfo" == "declare -A"* ]]
	then
		echo map
	elif [[ "$typeInfo" == "declare -i"* ]]
	then
		echo integer
	# elif [[ "${!1}" == "$obj:"* ]]
	# then
	# 	echo "$(Object.GetType "${!realObject}")"
	else
		echo string
	fi
}

Type.CreateVar() {
    # USE DEFAULT IFS IN CASE IT WAS CHANGED - important!
    local IFS=$' \t\n'

    local commandWithArgs=( $1 )
    local command="${commandWithArgs[0]}"

    shift

    if [[ "$command" == "trap" || "$command" == "l="* || "$command" == "_type="* ]]
    then
        return 0
    fi

    if [[ "${commandWithArgs[*]}" == "true" ]]
    then
        __typeCreate_next=true
        # Console.WriteStdErr "Will assign next one"
        return 0
    fi

    local varDeclaration="${commandWithArgs[*]:1}"
    if [[ $varDeclaration == '-'* ]]
    then
        varDeclaration="${commandWithArgs[*]:2}"
    fi
    local varName="${varDeclaration%%=*}"

    # var value is only important if making an object later on from it
    local varValue="${varDeclaration#*=}"

    # TODO: make this better:
    if [[ "$varValue" == "$varName" ]]
    then
    	local varValue=""
    fi

    if [[ ! -z $__typeCreate_varType ]]
    then
      # Console.WriteStdErr "SETTING $__typeCreate_varName = \$$__typeCreate_paramNo"
      # Console.WriteStdErr --
      #Console.WriteStdErr $tempName

    	DEBUG Log "creating $__typeCreate_varName ($__typeCreate_varType) = $__typeCreate_varValue"

    	if [[ -z "$__typeCreate_varValue" ]]
      then
        case "$__typeCreate_varType" in
          'array'|'map') eval "$__typeCreate_varName=()" ;;
          'string') eval "$__typeCreate_varName=''" ;;
          'integer') eval "$__typeCreate_varName=0" ;;
          * ) ;;
        esac
      fi

      case "$__typeCreate_varType" in
        'array'|'map'|'string'|'integer') ;;
        *)
          local return
          Object.New $__typeCreate_varType $__typeCreate_varName
          eval "$__typeCreate_varName=$return"
        ;;
      esac
      
      ## declare method with the name of the var ##
      eval "$__typeCreate_varName() {
        handleType $__typeCreate_varName \"\$@\";
      }"

    	# __oo__objects+=( $__typeCreate_varName )

      unset __typeCreate_varType
      unset __typeCreate_varValue
    fi

    if [[ "$command" != "declare" || "$__typeCreate_next" != "true" ]]
    then
        __typeCreate_normalCodeStarted+=1

        # Console.WriteStdErr "NOPASS ${commandWithArgs[*]}"
        # Console.WriteStdErr "normal code count ($__typeCreate_normalCodeStarted)"
        # Console.WriteStdErr --
    else
        unset __typeCreate_next

        __typeCreate_normalCodeStarted=0
        __typeCreate_varName="$varName"
        __typeCreate_varValue="$varValue"
        __typeCreate_varType="$__capture_type"
        __typeCreate_arrLength="$__capture_arrLength"

        # Console.WriteStdErr "PASS ${commandWithArgs[*]}"
        # Console.WriteStdErr --

        __typeCreate_paramNo+=1
    fi
}

Type.CaptureParams() {
    # Console.WriteStdErr "Capturing Type $_type"
    # Console.WriteStdErr --

    __capture_type="$_type"
}

# NOTE: true; true; at the end is required to workaround an edge case where TRAP doesn't behave properly
alias trapAssign='Type.CaptureParams; declare -i __typeCreate_normalCodeStarted=0; trap "declare -i __typeCreate_paramNo; Type.CreateVar \"\$BASH_COMMAND\" \"\$@\"; [[ \$__typeCreate_normalCodeStarted -ge 2 ]] && trap - DEBUG && unset __typeCreate_varType && unset __typeCreate_varName && unset __typeCreate_varValue && unset __typeCreate_paramNo" DEBUG; true; true; '
alias reference='_type=reference trapAssign declare -n'
alias string='_type=string trapAssign declare'
alias int='_type=integer trapAssign declare -i'
alias array='_type=array trapAssign declare -a'
alias map='_type=map trapAssign declare -A'

alias TestObject='_type=TestObject trapAssign declare'


### MAP 
## TODO: use vars, not $1-9 so references are resolved

map.set() {
  @resolveThis
  
  this["$1"]="$2"
  
  @return #this
}

map.delete() {
  @resolveThis
  
  unset this["$1"]
  
  @return #this
}

map.get() {
  @resolveThis

  local value="${this[$1]}"
  @return value
}

string.toUpper() {
  @resolveThis
  
  local value="hohoho"
  @return value
}

### /MAP

function core() {
  string justDoIt="yes!"
  map ramda=([test]=ho [great]=ok [test]="\$result ''ha'  ha" [enter]=$(printf "\na\nb\n"))
  
  # monad=true ramda set [ "one" "yep" ]
  ramda set [ "one" "yep" ]
  ramda set [ 'two' "oki  dokies" ]
  ramda delete [ enter ]
  ramda delete [ test ]
  ramda
  ramda get [ 'one' ]
  ramda get [ 'one' ] toUpper []
}

core

# invokeParams .doIt [ param1 param2 ] .property .doIt2 [ param1 param2 ] .doMore [] .more [ ] .anotherProp