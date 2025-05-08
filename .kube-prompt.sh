#!/bin/bash

__kube_ps1()
{
    if [ -z "$KUBE_INSTALLED" ]; then
	echo ""
    fi
    CONTEXT=$(cat ~/.kube/config | grep "current-context:" | sed "s/current-context: //")

    if [ -n "$CONTEXT" ]; then
	C_DEEPSKYBLUE='\e[38;5;39m'
	NO_FORMAT='\e[0m'
        echo -e "(k8s: ${C_DEEPSKYBLUE}${CONTEXT}${NO_FORMAT})"
    fi
}
