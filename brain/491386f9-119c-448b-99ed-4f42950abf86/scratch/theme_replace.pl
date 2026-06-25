#!/usr/bin/perl
use strict;
use warnings;

my $dir = '/mnt/c/Users/yu/code/TermiScope/mobile/flutter_app/lib';

process_dir($dir);

sub process_dir {
    my ($path) = @_;
    opendir my $dh, $path or die "Could not open directory $path: $!";
    my @entries = readdir $dh;
    closedir $dh;
    
    for my $entry (@entries) {
        next if $entry eq '.' || $entry eq '..';
        my $full_path = "$path/$entry";
        if (-d $full_path) {
            process_dir($full_path);
        } elsif (-f $full_path && $entry =~ /\.dart$/) {
            process_file($full_path);
        }
    }
}

sub process_file {
    my ($file) = @_;
    # Read as raw bytes (no :utf8 filter) to be completely encoding-agnostic
    open my $fh, '<', $file or die "Could not open $file for reading: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    
    my $changed = 0;
    if ($content =~ s/0xFF64D2FF/0xFFFF5C35/g) { $changed = 1; }
    if ($content =~ s/0xFF1E1E1E/0xFF0D0F18/g) { $changed = 1; }
    if ($content =~ s/0xFF2D2D2D/0xFF171B2D/g) { $changed = 1; }
    if ($content =~ s/0xFF404040/0xFF2D3354/g) { $changed = 1; }
    if ($content =~ s/0xFF32D74B/0xFF2ED573/g) { $changed = 1; }
    
    if ($changed) {
        # Write back as raw bytes exactly as is
        open my $ofh, '>', $file or die "Could not open $file for writing: $!";
        print $ofh $content;
        close $ofh;
        print "Updated: $file\n";
    }
}
