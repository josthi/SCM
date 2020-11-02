#!/usr/bin/perl



use File::Basename;
use File::Temp qw( tempfile tempdir) ;
use FileHandle;
use Text::ParseWords;
use POSIX qw( strftime ); 
use Cwd;
use Data::Dumper;
use Getopt::Long;
use DBI;


