# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2022 Best Practical Solutions, LLC
#                                          <sales@bestpractical.com>
#
# (Except where explicitly superseded by other copyright notices)
#
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
#
#
# CONTRIBUTION SUBMISSION POLICY:
#
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
#
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# END BPS TAGGED BLOCK }}}

=head1 NAME

RT::Action::ClearCustomFieldValues - clears all the values of a custom
field on a ticket.

=head1 DESCRIPTION

ClearCustomFieldValues is a ScripAction that will clear the values of a
custom field on a ticket.

Since it requires a Custom Field name or ID as an argument, you will need
to create a specific Action
with this ScripAction module and the desired Custom Field to be cleared.

B<IMPORTANT>: For multiple values custom fields, this action will clear
ll the values

=head1 USAGE

For example, you might have a date custom field 'Next Follow Up' which
should be cleared when a ticket is resolved because there will be no
future follow-ups to do.

The first step is to create a new Custom Action on Admin -> Global
-> Actions -> Create.

Here is an example of how to fill out the new Custom Action:

    Name: Clear Next Follow Up
    Description: Clear Next Follow Up custom field
    Action Module: ClearCustomFieldValues
    Parameters to Pass: Next Follow Up

B<P.S.>: On "Parameters to Pass", you can inform the name or the custom
field ID.

Finally, create a new Scrip with the Custom Action you have just created.
Go to Admin -> Scrips -> Create.

Fill out the new Scrip with the following information:

    Description: Clear Next Follow Up custom field on Resolve
    Condition: On Resolve
    Action: Clear Next Follow Up
    Template: Blank
    Stage: Normal

=cut

package RT::Action::ClearCustomFieldValues;
use base 'RT::Action';

use strict;
use warnings;

sub Describe  {
    my $self = shift;
    return (ref $self .
    " will clear the value of a custom field, provided as the Argument.");
}


sub Prepare  {
    my $self = shift;
    my $ticket = $self->TicketObj;

    # Check if custom field identifier is provided
    unless ( $self->Argument ) {
        RT->Logger->error(
            "No custom field identifier provided. Skipping..."
        );
        return 0;
    }

    # Check if custom field is available on this queue
    my $cf = $ticket->LoadCustomFieldByIdentifier($self->Argument);
    unless ( $cf->Id ) {
        RT->Logger->debug(
            "Uable to load custom field from $self->Argument"
        );
        return 0;
    }

    return 1;
}

sub Commit {
    my $self = shift;

    # Get the current value of the custom field
    my $ocfvs_obj = $self->TicketObj->CustomFieldValues($self->Argument);

    unless ( $ocfvs_obj->Count ) {
        return 0;
    }

    # For each value, delete it
    foreach my $cfvalue (@{$ocfvs_obj->ItemsArrayRef}) {
        my ($ret, $msg) = $self->TicketObj->DeleteCustomFieldValue(
            Field => $self->Argument,
            Value => $cfvalue->Content
        );
        unless ($ret) {
            RT->Logger->error(
                "Unable to delete custom field value $cfvalue: $msg"
            );
        }
    }

    return 1;
}

RT::Base->_ImportOverlays();

1;
