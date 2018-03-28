F5 Geolocation Data Updater
===========================

# Description

This utility can automatically download updated geolocation files from F5 downloads website (you need valid F5 account) and install it on your LTM devices.

SSH Password access should work provided you don't have any ssh-key on the profile, but key-based access should be preferred.

WIP !

## Configuration

## Usage

Create configuration file in ~/.config/f5updater/main.cnf based on sample in etc/main.cf.example

Setup Big-IP ssh access, optionnaly set ssh-key using ssh-copy-id.

Run f5updater.pl and see the magic happen
```
$EDIT
ssh-copy-id user@lb1
f5updater.pl
```

# Installation

## Dependencies

 * File::Homedir
 * Net::SSH::Perl
 * Net::SFTP
 * Config::General
 * Archive::Zip
 * WWW::Mechanize

Installing dependencies on debian:

``` shell
apt install libconfig-general-perl libfile-homedir-perl libarchive-zip-perl libwww-mechanize-perl
cpan -i Net::SSH::Perl Net::SFTP
```

# TDL

 * Command-line parsing, debug/verbose/upload/download
 * Color output
 * Enhance error handling
 * Ask F5 for a few usefull enhancement :)
   * RSS Feed with releases ?
   * Download API ?
   * BigIP iConnectREST endpoint for geoloc update ?
