#!/usr/bin/perl
# Loads CasementMediaRemote.dylib into this Apple-signed perl process and runs it.
# Usage: /usr/bin/perl casement-mediaremote.pl /path/to/CasementMediaRemote.dylib
use strict;
use warnings;
use DynaLoader;

my $lib = shift @ARGV or die "usage: casement-mediaremote.pl <CasementMediaRemote.dylib>\n";
my $handle = DynaLoader::dl_load_file($lib, 0) or die "load failed: " . DynaLoader::dl_error() . "\n";
my $sym = DynaLoader::dl_find_symbol($handle, "casement_mediaremote_main") or die "symbol missing: " . DynaLoader::dl_error() . "\n";
DynaLoader::dl_install_xsub("main::casement_mediaremote_main", $sym);
casement_mediaremote_main();
