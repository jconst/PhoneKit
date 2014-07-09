#!/bin/bash

prefix=${1:-twilio_}

cat <<EOH
/*
 * This is a generated header; do not edit!
 */

#ifndef _NAMESPACING_PREFIX_HEADER_H_
#define _NAMESPACING_PREFIX_HEADER_H_

#ifndef TWILIO_PJPROJECT_DONT_REWRITE_SYMBOLS

EOH

while read line; do
    echo "#define $line $prefix$line"
done

cat <<EOF

#endif /* !TWILIO_PJPROJECT_DONT_REWRITE_SYMBOLS */
#endif  /* !_NAMESPACING_PREFIX_HEADER_H_ */
EOF
