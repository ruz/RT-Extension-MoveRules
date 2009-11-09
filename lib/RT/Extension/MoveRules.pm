use 5.008003;
use strict;
use warnings;

package RT::Extension::MoveRules;

our $VERSION = '0.01';

=head1 NAME

RT::Extension::MoveRules - control ticket movements between queues

=head1 DESCRIPTION

If you move tickets between queues a lot then probably you want
to control this process. This extension allows you to configure
rules which are required to move a ticket from a queue to another
queue, for example if custom field X is equal to Y then a ticket
can be moved from queue A to B. As well you can define which
fields should be set before move.

=cut

$RT::Config::META{'MoveRules'} = {
    Type => 'ARRAY',
};


{ my $cache;
sub Config {
    my $self = shift;
    return $cache if $cache;

    $cache = {};
    foreach my $rule ( RT->Config->Get('MoveRules') ) {
        $cache->{ lc $rule->{'From'} }{ lc $rule->{'To'} }
            = { %$rule };
    }
    return $cache;
} }

use RT::Condition::Complex;


sub Check {
    my $self = shift;
    my %args = (
        From => undef, To => undef,
        Ticket => undef,
        @_
    );

    my $config = $self->Config->{ lc $args{'From'}->Name }
        ->{ lc $args{'To'}->Name };
    unless ( $config ) {
        return (0, $args{'Ticket'}->loc('Ticket move to that queue is not allowed'));
    }

    if ( my $rule = $config->{'Rule'} ) {
        my $cond = RT::Condition::Complex->new(
            TicketObj      => $args{'Ticket'},
            TransactionObj => $args{'Transaction'},
            CurrentUser    => $RT::SystemUser,
        );
        my ($res, $tree, $desc) = $cond->Solve(
            $rule, '' => $args{'Ticket'}, From => $args{'From'}, To => $args{'To'},
        );
        return (0, $args{'Ticket'}->loc('Ticket can not be moved, the following rules are not met: [_1]', $desc))
            unless $res;
    }
    return 1;
}

use RT::Ticket;
package RT::Ticket;

{
    my $old_sub = \&RT::Ticket::SetQueue;
    no warnings 'redefine';
    *RT::Ticket::SetQueue = sub {
        my $self = shift;
        return $old_sub->( $self, @_ ) unless $self->Type eq 'ticket';

        my $new_id = shift;

        # we have to duplicate some code

        my $new = RT::Queue->new( $self->CurrentUser );
        $new->Load( $new_id );
        unless ( $new->id ) {
            return (0, $self->loc("That queue does not exist"));
        }

        my $old = $self->QueueObj;
        if ( $old->id == $new->id ) {
            return ( 0, $self->loc('That is the same value') );
        }

        my ($status, $msg) = RT::Extension::MoveRules->Check(
            From => $old, To => $new,
            Ticket => $self,
        );
        return ($status, $msg) unless $status;

        return $old_sub->( $self, $new_id, @_ );
    }
}

=head1 LICENSE

Under the same terms as perl itself.

=head1 AUTHOR

Ruslan Zakirov E<lt>Ruslan.Zakirov@gmail.comE<gt>

=cut

1;
