#!/usr/local/bin/bash

input_file=$1
output_file=$2

perl -pe 's/\[\[([^\]]+)\]\]/do { my $text = $1; my $path = lc($1); $path =~ s| |-|g; "[$text](\/texts\/$path)" }/ge' "$input_file" > "$output_file"
