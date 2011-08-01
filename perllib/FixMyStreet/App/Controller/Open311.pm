package FixMyStreet::App::Controller::Open311;

use utf8;
use Moose;
use namespace::autoclean;

use JSON;
use XML::Simple;
use DateTime::Format::W3CDTF;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

FixMyStreet::App::Controller::Open311 - Catalyst Controller

=head1 DESCRIPTION

Open311 server API

Open311 server API for Open311 clients

http://open311.org/
http://wiki.open311.org/GeoReport_v2
http://fixmystreet.org.nz/api
http://seeclickfix.com/open311/

Issues with Open311
 * no way to specify which languages are understood by the
   recipients.  some lang=nb,nn setting should be available.
 * not obvious how to handle generic requests (ie without lat/lon
   values).
 * should service IDs be numeric or not?  Spec do not say, and all
   examples I find use numbers.
 * missing way to search for reports near a location using lat/lon
 * report attributes lack title field.
 * missing way to provide updates information for a request
 * should support GeoRSS output as well as json and home made XML

=head1 METHODS

=cut

=head2 index

Displays some summary information for the requests.

=cut

sub index : Path : Args(0) {
    my ( $self, $c ) = @_;
    # don't need to do anything here - should just pass through.
}

sub old_uri : Regex('^open311\.cgi') : Args(0) {
    my ( $self, $c ) = @_;
    ( my $new = $c->req->path ) =~ s/open311.cgi/open311/;
    $c->res->redirect( "/$new", 301);
}

=head2 discovery

http://search.cpan.org/~bobtfish/Catalyst-Manual-5.8007/lib/Catalyst/Manual/Intro.pod

=cut

sub discovery_v2 : LocalRegex('^v2/discovery.(xml|json|html)$') : Args(0) {
    my ( $self, $c ) = @_;
    $c->stash->{format} = $c->req->captures->[0];
    $c->forward( 'get_discovery' );
}

sub services_v2 : LocalRegex('^v2/services.(xml|json|html)$') : Args(0) {
    my ( $self, $c ) = @_;
    $c->stash->{format} = $c->req->captures->[0];
    $c->forward( 'get_services' );
}

sub requests_v2 : LocalRegex('^v2/requests.(xml|json|html|rss)$') : Args(0) {
    my ( $self, $c ) = @_;
    $c->stash->{format} = $c->req->captures->[0];
    $c->forward( 'get_requests' );
}

sub request_v2 : LocalRegex('^v2/requests/(\d+).(xml|json|html)$') : Args(0) {
    my ( $self, $c ) = @_;
    $c->stash->{id}     = $c->req->captures->[0];
    $c->stash->{format} = $c->req->captures->[1];
    $c->forward( 'get_request' );
}

sub error : Private {
    my ( $self, $c, $error ) = @_;
    $c->stash->{error} = "ERROR: $error";
    $c->stash->{template} = 'open311/index.html';
}

# Example
# http://sandbox.georeport.org/tools/discovery/discovery.xml
sub get_discovery : Private {
    my ( $self, $c ) = @_;

    my $contact_email = $c->config->{CONTACT_EMAIL};
    my $prod_url = 'http://www.fiksgatami.no/open311';
    my $test_url = 'http://fiksgatami-dev.nuug.no/open311';
    my $prod_changeset = '2011-04-08T00:00:00Z';
    my $test_changeset = $prod_changeset;
    my $spec_url = 'http://wiki.open311.org/GeoReport_v2';
    my $info =
    {
        'contact' => ["Send email to $contact_email."],
        'changeset' => [$prod_changeset],
        # XXX rewrite to match
        'key_service' => ["Read access is open to all according to our \u003Ca href='/open_data' target='_blank'\u003Eopen data license\u003C/a\u003E. For write access either: 1. return the 'guid' cookie on each call (unique to each client) or 2. use an api key from a user account which can be generated here: http://seeclickfix.com/register The unversioned url will always point to the latest supported version."],
        'max_requests' => [ $c->config->{RSS_LIMIT} ],
        'endpoints' => [
            {
                'endpoint' => [
                    {
                        'formats' => [
                            {'format' => [ 'text/xml',
                                           'application/json',
                                           'text/html' ]
                            }
                            ],
                        'specification' => [ $spec_url ],
                        'changeset' => [ $prod_changeset ],
                        'url' => [ $prod_url ],
                        'type' => [ 'production' ]
                    },
                    {
                        'formats' => [
                            {
                                'format' => [ 'text/xml',
                                              'application/json',
                                              'text/html' ]
                            }
                            ],
                        'specification' => [ $spec_url ],
                        'changeset' => [ $test_changeset ],
                        'url' => [ $test_url ],
                        'type' => [ 'test' ]
                    }
                    ]
            }
            ]
    };
    $c->forward( 'format_output', [ {
        'discovery' => $info
    } ] );
}

# Example
# http://seeclickfix.com/open311/services.html?lat=32.1562864999991&lng=-110.883806
sub get_services : Private {
    my ( $self, $c ) = @_;

    my $jurisdiction_id = $c->req->param('jurisdiction_id') || '';
    my $lat = $c->req->param('lat') || '';
    my $lon = $c->req->param('long') || '';

    # Look up categories for this council or councils
    my $categories = $c->model('DB::Contact')->not_deleted;

    if ($lat || $lon) {
        my @area_types = $c->cobrand->area_types;
        my $all_councils = mySociety::MaPit::call('point',
                                                  "4326/$lon,$lat",
                                                  type => \@area_types);
        $categories = $categories->search( {
            area_id => [ keys %$all_councils ],
        } );
    }

    my @categories = $categories->search( undef, {
        columns => [ 'category' ],
        distinct => 1,
    } )->all;

    my @services;
    for my $categoryref ( sort { $a->category cmp $b->category }
                          @categories) {
        my $categoryname = $categoryref->category;
        push(@services,
             {
                 # FIXME Open311 v2 seem to require all three, and we
                 # only have one value.
                 'service_name' => [ $categoryname ],
                 'description' =>  [ $categoryname ],
                 'service_code' => [ $categoryname ],
                 'metadata' => [ 'false' ],
                 'type' => [ 'realtime' ],
#                 'group' => [ '' ],
#                 'keywords' => [ '' ],
             }
            );
    }
    $c->forward( 'format_output', [ {
        'services' => [ {
            'service' => \@services
        } ]
    } ] );
}


sub output_requests : Private {
    my ( $self, $c, $criteria, $limit ) = @_;
    $limit = $c->config->{RSS_LIMIT}
        unless $limit && $limit <= $c->config->{RSS_LIMIT};

    my $attr = {
        order_by => { -desc => 'confirmed' },
        rows => $limit
    };

    # Look up categories for this council or councils
    my $problems = $c->cobrand->problems->search( $criteria, $attr );

    my %statusmap = ( 'fixed' => 'closed',
                      'confirmed' => 'open');

    my @problemlist;
    my @councils;
    while ( my $problem = $problems->next ) {
        my $id = $problem->id;

        $problem->service( 'Web interface' ) unless $problem->service;

        if ($problem->council) {
            (my $council = $problem->council) =~ s/\|.*//g;
            my @council_ids = split(/,/, $council);
            push(@councils, @council_ids);
            $problem->council( \@council_ids );
        }

        $problem->state( $statusmap{$problem->state} );

        my $request =
        {
            'service_request_id' => [ $id ],
            'title' => [ $problem->title ], # Not in Open311 v2
            'detail'  => [ $problem->detail ], # Not in Open311 v2
            'description' => [ $problem->title .': ' . $problem->detail ],
            'lat' => [ $problem->latitude ],
            'long' => [ $problem->longitude ],
            'status' => [ $problem->state ],
#            'status_notes' => [ {} ],
            'requested_datetime' => [ w3date($problem->confirmed_local) ],
            'updated_datetime' => [ w3date($problem->lastupdate_local) ],
#            'expected_datetime' => [ {} ],
#            'address' => [ {} ],
#            'address_id' => [ {} ],
            'service_code' => [ $problem->category ],
            'service_name' => [ $problem->category ],
#            'service_notice' => [ {} ],
            'agency_responsible' =>  $problem->council , # FIXME Not according to Open311 v2
#            'zipcode' => [ {} ],
            'interface_used' => [ $problem->service ], # Not in Open311 v2
        };

        if ( !$problem->anonymous ) {
            # Not in Open311 v2
            $request->{'requestor_name'} = [ $problem->name ];
        }
        if ( $problem->whensent ) {
            # Not in Open311 v2
            $request->{'agency_sent_datetime'} =
                [ w3date($problem->whensent_local) ];
        }

        # Extract number of updates
        my $updates = $problem->comments->search(
            { state => 'confirmed' },
        )->count;
        if ($updates) {
            # Not in Open311 v2
            $request->{'comment_count'} = [ $updates ];
        }

        my $display_photos = $c->cobrand->allow_photo_display;
        if ($display_photos && $problem->photo) {
            my $url = $c->cobrand->base_url();
            my $imgurl = $url . "/photo?id=$id";
            $request->{'media_url'} = [ $imgurl ];
        }
        push(@problemlist, $request);
    }
    my $areas_info = mySociety::MaPit::call('areas', \@councils);
    foreach my $request (@problemlist) {
        if ($request->{agency_responsible}) {
            my @council_names = map { $areas_info->{$_}->{name} } @{$request->{agency_responsible}} ;
            $request->{agency_responsible} =
                [ {'recipient' => [ @council_names ] } ];
        }
    }
    $c->forward( 'format_output', [ {
        'requests' => [ {
            'request' => \@problemlist
        } ]
    } ] );
}

sub get_requests : Private {
    my ( $self, $c ) = @_;

    $c->forward( 'is_jurisdiction_id_ok' );

    my $max_requests = $c->req->param('max_requests') || 0;

    # Only provide access to the published reports
    my $criteria = {
        state => [ 'fixed', 'confirmed' ]
    };

    my %rules = (
        service_request_id => [ '=', 'id' ],
        service_code       => [ '=', 'category' ],
        status             => [ '=', 'state' ],
        start_date         => [ '>=', 'confirmed' ],
        end_date           => [ '<', 'confirmed' ],
        agency_responsible => [ '~', 'council' ],
        interface_used     => [ '=', 'service' ],
        has_photo          => [ '=', 'photo' ],
    );
    for my $param (keys %rules) {
        my $value = $c->req->param($param);
        next unless $value;
        my $op  = $rules{$param}[0];
        my $key = $rules{$param}[1];
        if ( 'status' eq $param ) {
            $value = {
                'open' => 'confirmed',
                'closed' => 'fixed'
            }->{$value};
        } elsif ( 'agency_responsible' eq $param ) {
            my @valuelist;
            for my $agency (split(/\|/, $value)) {
                unless ($agency =~ m/^(\d+)$/) {
                    $c->detach( 'error', [
                        sprintf(_('Invalid agency_responsible value %s'),
                            $value)
                    ] );
                }
                my $agencyid = $1;
                # FIXME This seem to match the wrong entries
                # some times.  Not sure when or why
                my $re = "(\\y$agencyid\\y|^$agencyid\\y|\\y$agencyid\$)";
                push(@valuelist, $re);
            }
            $value = \@valuelist;
        } elsif ( 'has_photo' eq $param ) {
            $value = undef;
            $op = '!=' if 'true' eq $value;
            $c->detach( 'error', [
                sprintf(_('Incorrect has_photo value "%s"'),
                    $value)
            ] )
                unless 'true' eq $value || 'false' eq $value;
        } elsif ( 'interface_used' eq $param ) {
            $value = undef if 'Web interface' eq $value;
        }
        $criteria->{$key} = { $op, $value };
    }

    if ('rss' eq $c->stash->{format}) {
# FIXME write new implementatin
#        my $cobrand = Page::get_cobrand($c);
#        my $alert_type = 'open311_requests_rss';
#        my $xsl = $c->cobrand->feed_xsl;
#        my $qs = '';
#        my %title_params;
#        my $out =
#            FixMyStreet::Alert::generate_rss('new_problems', $xsl,
#                                             $qs, \@args,
#                                             \%title_params, $cobrand,
#                                             $c, $criteria, $max_requests);
#        print $c->header( -type => 'application/xml; charset=utf-8' );
#        print $out;
        $c->stash->{type} = 'new_problems';
        $c->stash->{search_criteria} = $criteria;
        $c->stash->{max_requests} = $max_requests;
        $c->stash->{query_func} = '/open311/rss_query';
        $c->forward( '/rss/output' );
    } else {
        $c->forward( 'output_requests', [ $criteria, $max_requests ] );
    }
}

# Based on Controller::Rss::query_main
sub rss_query : Private {
    my ( $self, $c ) = @_;

    my $limit = $c->stash->{max_requests};
    $limit = $c->config->{RSS_LIMIT}
        unless $limit && $limit <= $c->config->{RSS_LIMIT};

    my $attr = {
        order_by => { -desc => 'confirmed' },
        rows => $limit
    };

    my $problems = $c->cobrand->problems->search( $criteria, $attr );
    $c->stash->{query_main} = $problems;
}

# Example
# http://seeclickfix.com/open311/requests/1.xml?jurisdiction_id=sfgov.org
sub get_request : Private {
    my ( $self, $c ) = @_;
    my $format = $c->stash->{format};
    my $id     = $c->stash->{id};

    $c->forward( 'is_jurisdiction_id_ok' );

    if ('html' eq $format) {
        my $base_url = $c->cobrand->base_url();
        $c->res->redirect($base_url . "/report/$id");
        return;
    }

    my $criteria = {
        state => [ 'fixed', 'confirmed' ],
        id => $id,
    };
    $c->forward( 'output_requests', [ $criteria ] );
}

sub format_output : Private {
    my ( $self, $c, $hashref ) = @_;
    my $format = $c->stash->{format};
    if ('json' eq $format) {
        $c->res->content_type('application/json; charset=utf-8');
        $c->res->body( encode_json($hashref) );
    } elsif ('xml' eq $format) {
        $c->res->content_type('application/xml; charset=utf-8');
        $c->res->body( XMLout($hashref, RootName => undef) );
    } else {
        $c->detach( 'error', [
            sprintf(_('Invalid format %s specified.'), $format)
        ] );
    }
}

sub is_jurisdiction_id_ok : Private {
    my ( $self, $c ) = @_;
    unless (my $jurisdiction_id = $c->req->param('jurisdiction_id')) {
        $c->detach( 'error', [ _('Missing jurisdiction_id') ] );
    }
}

# Input:  DateTime object
# Output: 2011-04-23T10:28:55+02:00
# FIXME Need generic solution to find time zone
sub w3date : Private {
    my $datestr = shift;
    return unless $datestr;
    return DateTime::Format::W3CDTF->format_datetime($datestr);
}

=head1 AUTHOR

Copyright (c) 2011 Petter Reinholdtsen, some rights reserved.
Email: pere@hungry.com

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the  GPL v2 or later.

=cut

__PACKAGE__->meta->make_immutable;

1;
