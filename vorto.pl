#!/usr/bin/perl

use utf8;
use strict;
use warnings;
use DateTime;
use LWP;


use constant URL=> "http://35.200.13.75";
#use constant URL=> "http://localhost:8080";

#-----------------------------------------
use constant MAXLEN=>1000;

sub  trim {
  my $s = shift;
  $s =~ s/^\s+|\s+$//g;
  return $s;
}

# GET /path HTTP/1.0
sub get_first_line {
  my $ln=<STDIN>;
  $ln=~ s/[\r\n]*$//;
  split ' ', $ln, 3;
}

sub get_headers {
  my $result={};
  while (my $ln=<STDIN>) {
    $ln=~ s/[\r\n]*$//;
    last unless $ln;

    #print STDERR "-- $ln\n";
    my @v= split ':', $ln, 2;
    my $name= lc trim($v[0]);
    my $val= trim($v[1]);
    $result->{$name}= $val;
  }
  return $result;
}

sub get_body {
  my ($method, $len)= @_;
  my $body= "";

  if ($len>MAXLEN) {
    $len= MAXLEN;
  }
  read(STDIN, $body, $len) if $len>0;
  return $body;
}

sub respond {
  my ($status, $headers, $body)= @_;

  my $date= DateTime->now()->strftime("%a, %e %b %Y %H:%M:%S GMT");
  my $content_length= length($body);

  print "HTTP/1.0 $status->[0] $status->[1]\r\n";
  while (my ($name, $val)= each %{$headers}) {
    print "$name: $val\r\n";
  }
  print "Date: $date\r\n";
  print "Content-Length: $content_length\r\n";
  print "\r\n";
  print $body;
}

#-----------------------------------------

sub redirect_get {
  my ($url, $path, $headers)= @_;

  my $agent= LWP::UserAgent->new;
  #$agent->agent("MyAgent/0.1");
  $agent->timeout(3);

  #my $xxx= $url . $path;
  #print STDERR "-- $xxx\n";
  my $resp= $agent->get($url . $path); # or die "...";
  if ($resp->is_success) {
    return [$resp->content_type, $resp->decoded_content];
  } else {
    return ["ERROR", $resp->status_line];
  }
}

sub redirect_post {
  my ($url, $path, $headers, $body)= @_;
  
  my $agent= LWP::UserAgent->new;
  #$agent->agent("MyAgent/0.1");
  $agent->timeout(3);

  # TODO content-type ?
  my $resp= $agent->post($url . $path, Content => $body);

  #my $req= HTTP::Request->new(POST => URL . "/search");
  #print "req 1--\n";
  #$req->content_type("text/plain");
  #print "req 2--\n";
  #$req->content($body);
  #print "req 3--\n";
  #$resp= $agent->request($req);

  if ($resp->is_success) {
    return [$resp->content_type, $resp->decoded_content];
  } else {
    return ["ERROR", $resp->status_line];
  }
}

#-----------------------------------------

# MAIN

#--- Receive
my ($method, $path, $ver)= get_first_line();
my $headers= get_headers();
my $content_length= ($headers->{'content-length'} || 0);
my $body= get_body($method, $content_length);

#print STDERR "-- $method; $path; $ver\n";
#print STDERR "-- $content_length\n";
#print STDERR "-- $body\n";

#--- Redirect
my $ret=[];
if ($method eq "GET") {
  $ret= redirect_get(URL, $path, $headers);
} elsif ($method eq "POST") {
  $ret= redirect_post(URL, $path, $headers, $body);
}
my ($content_type, $resp_body)= @{$ret};

my $resp_headers={
  "Cache-Control"=>"no-cache",
  "Content-Type"=>"text/plain"
};

#--- Send back
my $stat= [200, "OK"];
if ($content_type eq "ERROR") {
  $stat= [400, "ERROR"];
}
respond($stat, $resp_headers, $resp_body);


#print $q->header("text/plain");



# vim: ts=2 sw=2 et
