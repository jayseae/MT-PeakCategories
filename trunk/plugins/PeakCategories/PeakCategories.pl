# ===========================================================================
# Copyright 2005, Everitz Consulting (mt@everitz.com)
# ===========================================================================
package MT::Plugin::PeakCategories;

use base qw(MT::Plugin);
use strict;

use MT;
use MT::Util qw(format_ts offset_time_list);

# version
use vars qw($VERSION);
$VERSION = '1.0.0';

my $about = {
  name => 'MT-PeakCategories',
  description => 'Provides a list of recently used categories.',
  author_name => 'Everitz Consulting',
  author_link => 'http://www.everitz.com/',
  version => $VERSION,
};
MT->add_plugin(new MT::Plugin($about));

use MT::Template::Context;
MT::Template::Context->add_container_tag(PeakCategories => \&PeakCategories);

MT::Template::Context->add_tag(PeakCategoriesFirstPost => \&ReturnValue);
MT::Template::Context->add_tag(PeakCategoriesLastPost => \&ReturnValue);

sub PeakCategories {
  my($ctx, $args, $cond) = @_;

  # set time frame
  my $days = $args->{days} || 7;
  return $ctx->error("Invalid data: [_1] must be numeric!", qq(<MTPeakCategories days="$days">)) unless ($days =~ /\d*/);
  my @ago = offset_time_list(time - 60 * 60 * 24 * $days);
  my $ago = sprintf "%04d%02d%02d%02d%02d%02d", $ago[5]+1900, $ago[4]+1, @ago[3,2,1,0];
  my @now = offset_time_list(time);
  my $now = sprintf "%04d%02d%02d%02d%02d%02d", $now[5]+1900, $now[4]+1, @now[3,2,1,0];

  my (%args, %terms);
  $terms{'status'} = MT::Entry::RELEASE();
  $terms{'created_on'} = [ $ago, $now ];
  $args{'direction'} = 'descend';
  $args{'range'} = { created_on => 1 };

  my %cats;
  require MT::Entry;
  my $iter = MT::Entry->load_iter(\%terms, \%args);
  while (my $obj = $iter->()) {
    require MT::Placement;
    my $place = MT::Placement->load({
      entry_id => $obj->id,
      is_primary => 1
    });
    next unless ($place);
    $cats{'count-'.$place->category_id}++;
    $cats{'first-'.$place->category_id} = $obj->created_on;
    if ($cats{'count-'.$place->category_id} == 1) {
      $cats{'last-'.$place->category_id} = $obj->created_on;
    }
  }

  my @cats = sort { $cats{$b} cmp $cats{$a} } keys %cats;
  #@entries = sort { $b->created_on cmp $a->created_on } @entries;

  my $builder = $ctx->stash('builder');
  my $tokens = $ctx->stash('tokens');
  my $res = '';

  foreach my $cat (@cats) {
    $cat =~ s/^count-//;
    require MT::Category;
    my $category = MT::Category->load($cat);
    next unless ($category);
    eval ("use MT::Promise qw(delay);");
    $ctx->{__stash}{category} = $category if $@;
    $ctx->{__stash}{category} = delay (sub { $category; }) unless $@;
    $ctx->{__stash}{category_count} = $cats{'count-'.$category->id};
    $ctx->{__stash}{PeakCategoriesFirstPost} = $cats{'first-'.$category->id};
    $ctx->{__stash}{PeakCategoriesLastPost} = $cats{'last-'.$category->id};
    my $out = $builder->build($ctx, $tokens);
    return $ctx->error($builder->errstr) unless defined $out;
    $res .= $out;
  }
  $res;
}

sub ReturnValue {
  my ($ctx, $args) = @_;
  my $val = $ctx->stash($ctx->stash('tag'));
  if (my $fmt = $args->{format}) {
    if ($val =~ /^[0-9]{14}$/) {
      return format_ts($fmt, $val, $ctx->stash('blog'));
    }
  }
  $val;
}

1;