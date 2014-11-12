{
	PERCENT=0;
	PERCENTTEMP=$0;
	sub(/^.*[[:space:]]/, "", PERCENTTEMP);
	sub(/%$/, "", PERCENTTEMP);
	# check number
	if (PERCENTTEMP ~ /^[0-9]+$/) {
		PERCENT=PERCENTTEMP;
		BLOCKS=$0;
		sub(/^[^\]]*\][[:space:]]+/, "", BLOCKS);
		sub(/[[:space:]]+[0-9]+%$/, "", BLOCKS);
		sub(/\//, " of ", BLOCKS);
		print PERCENT;
		print "XXX";
		print MSG;
		print " => ";
		print BLOCKS;
		print "XXX";
	} else {
		print "XXX";
		print MSG;
		print " => ";
		print "Progress Indicator Frozen at " PERCENT "% (but no errors seen)"
		print "XXX";
	}
	system("");
}
