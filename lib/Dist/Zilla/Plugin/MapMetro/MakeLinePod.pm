use 5.10.1;
use strict;
use warnings;
use utf8;

package Dist::Zilla::Plugin::MapMetro::MakeLinePod;

# VERSION

use Moose;
use namespace::sweep;
use Path::Tiny;
use List::AllUtils qw/any all uniq/;
use Types::Standard qw/Str Maybe/;
use Map::Metro::Shim;

use Dist::Zilla::File::InMemory;
with 'Dist::Zilla::Role::FileGatherer';

has cityname => (
    is => 'rw',
    isa => Maybe[Str],
    predicate => 1,
);

sub gather_files {
    my $self = shift;
    my $arg = shift;

    return if !$ENV{'MMLINEPOD'};

    my @cities = path(qw/lib Map Metro Plugin Map/)->children(qr/\.pm/);
    return if !scalar @cities;

    my @mapfiles = path('share')->children(qr{map-.*\.metro});
    return if !scalar @mapfiles;

    my $city = (shift @cities)->basename;
    $city =~ s{\.pm}{};
    my $mapfile = shift @mapfiles;

    my $graph = Map::Metro::Shim->new(filepath => $mapfile)->parse;

    my @linepod = ();

    LINE:
    foreach my $line ($graph->all_lines) {

        my @stations = $graph->filter_stations(sub {
            my $station = $_;
            return any { $_->id eq $line->id } $station->all_lines;
        });
        $self->log(sprintf 'Line %s, found %s stations', $line->name, scalar @stations);

        my @routes;
        ORIGIN:
        foreach my $i (0 .. $#stations) {
            my $origin_station = $stations[ $i ];

            DESTINATION:
            foreach my $j (0 .. $#stations) {
                my $destination_station = $stations[ $j ];
                next DESTINATION if $origin_station->id == $destination_station->id;

                my $route = $graph->routing_for($origin_station->id, $destination_station->id)->get_route(0);
                push @routes => $route if defined $route;
            }
        }

        $self->log(sprintf 'Line %s, found %s routes', $line->name, scalar @routes);
        my $chosen_route = (sort { $b->step_count <=> $a->step_count } @routes)[0];

        my @station_pod;
        foreach my $step ($chosen_route->all_steps) {
            my $change_to_string = $self->make_change_to_string($graph, $step->origin_line_station);
            push @station_pod => sprintf '    %s %s', $step->origin_line_station->station->name, $change_to_string;

            if(!$step->has_next_step) {
                my $change_to_string = $self->make_change_to_string($graph, $step->destination_line_station);
                push @station_pod => sprintf '    %s %s', $step->destination_line_station->station->name, $change_to_string;
            }
        }

        push @linepod => sprintf '=head2 %s: %s → %s' => $line->description,
                                                          $chosen_route->get_step(0)->origin_line_station->station->name,
                                                          $chosen_route->get_step(-1)->destination_line_station->station->name;

        push @linepod => '', @station_pod, '';

    }

    my $file = Dist::Zilla::File::InMemory->new(
        name => "lib/Map/Metro/Plugin/Map/$city/Lines.pm",
        content => $self->make_line_contents($city, @linepod),
    );
    $self->add_file($file);

    return;
}

sub make_change_to_string {
    my $self = shift;
    my $graph = shift;
    my $line_station = shift;

    my @change_strings = ();
    my @other_lines = $line_station->station->filter_lines(sub { $_->id ne $line_station->line->id });
    push @change_strings => scalar @other_lines ? sprintf '(%s)', join ', ' => map { $_->name } @other_lines
                         :                       ()
                         ;

    my @transfers = $graph->filter_transfers(sub { $_->origin_station->id == $line_station->station->id });
    push @change_strings => scalar @transfers ? join ' ' => map {
                                                                sprintf ('[%s: %s]', $_->destination_station->name,
                                                                                     join ', ' => map { $_->name } $_->destination_station->all_lines ) } @transfers
                         :                      ()
                         ;

    @transfers = $graph->filter_transfers(sub { $_->destination_station->id == $line_station->station->id });
    push @change_strings => scalar @transfers ? join ' ' => map {
                                                                sprintf ('[%s: %s]', $_->origin_station->name,
                                                                                     join ', ' => map { $_->name } $_->origin_station->all_lines ) } @transfers
                         :                      ()
                         ;

    return join ' ' => @change_strings;
}

sub make_line_contents {
    my $self = shift;
    my $city = shift;
    my $content = join "\n" => @_;

return qq{
package Map::Metro::Plugin::Map::${city}::Lines;

# VERSION

1;

__END__

=encoding utf-8

=head1 NAME

Map::Metro::Plugin::Map::${city}::Lines - Detailed information about Map::Metro::Plugin::Map::$city

=head1 LINES

$content

=head1 SEE ALSO

L<Map::Metro::Plugin::Map::$city>

};
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=encoding utf-8

=head1 NAME

Dist::Zilla::Plugin::MapMetro::MakeLinePod - Short intro

=head1 SYNOPSIS

  use Dist::Zilla::Plugin::MapMetro::MakeLinePod;

=head1 DESCRIPTION

Dist::Zilla::Plugin::MapMetro::MakeLinePod is ...

=head1 SEE ALSO


=head1 AUTHOR

Erik Carlsson E<lt>info@code301.comE<gt>

=head1 COPYRIGHT

Copyright 2015 - Erik Carlsson

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
