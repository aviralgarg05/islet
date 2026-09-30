#!/usr/bin/perl
# Loads IsletMediaRemote.dylib into this Apple-signed perl process and runs it.
# Usage: /usr/bin/perl islet-mediaremote.pl /path/to/IsletMediaRemote.dylib
use strict;
use warnings;
use DynaLoader;

my $lib = shift @ARGV or die "usage: islet-mediaremote.pl <IsletMediaRemote.dylib>\n";
my $handle = DynaLoader::dl_load_file($lib, 0) or die "load failed: " . DynaLoader::dl_error() . "\n";
my $sym = DynaLoader::dl_find_symbol($handle, "islet_mediaremote_main") or die "symbol missing: " . DynaLoader::dl_error() . "\n";
DynaLoader::dl_install_xsub("main::islet_mediaremote_main", $sym);
islet_mediaremote_main();
