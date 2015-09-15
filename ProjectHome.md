Work in progress here.



# What #
This is a complete rework of the existing pentoo-installer.
It will be proposed to the Pentoo team when it's fully functional.

# Installation #
Todo

# Why #
The official Pentoo installer is awesome:
  * Pentoo/Gentoo out of the box!
  * Supports encrypted partitions
  * Offers hardened and binary profiles
  * Sane start-to-end installation

That being said, I personally dont like these things about it:
  * One large script
  * Global variables throughout it, not all functions declare variables as local
  * Mixed code style

# Differences to official installer #
Incomplete list:
  * Installation split up into several independent scripts
  * dialog/Xdialog write to STDOUT, no need for temp files
  * overall less use of temp files
  * much stricter error handling
  * improved cleanup when restarting after an exit
  * fixed a lot of bugs, tried hard not to introduce new ones ;)
  * Strict code style