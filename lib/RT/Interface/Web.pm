## $Header$
## Copyright 2000 Jesse Vincent <jesse@fsck.com> & Tobias Brox <tobix@fsck.com>
## Request Tracker is Copyright 1996-2000 Jesse Vincent <jesse@fsck.com>

## This is a library of static subs to be used by the Mason web
## interface to RT

package RT::Interface::Web;

# {{{ sub NewParser

=head2 NewParser

  Returns a new Mason::Parser object. Takes a param hash of things 
  that get passed to HTML::Mason::Parser. Currently hard coded to only
  take the parameter 'allow_globals'.

=cut

sub NewParser {
    my %args = ( allow_globals => undef,
                 @_ );

    my $parser = new HTML::Mason::Parser( 
                        default_escape_flags=>'h',
                        allow_globals => $args{'allow_globals'}
					);
    return($parser);
}

# }}}

# {{{ sub NewInterp

=head2 NewInterp 

  Takes a paremeter hash. Needs a param called 'parser' which is a reference
  to an HTML::Mason::Parser.
  returns a new Mason::Interp object

=cut

sub NewInterp {
    my %params = ( allow_recursive_autohandlers => 1,
                   comp_root => "$RT::MasonComponentRoot",
                   data_dir => "$RT::MasonDataDir",
                   parser => undef,
                   @_);
    
    #We allow recursive autohandlers to allow for RT auth.

    use HTML::Mason::Interp;
    my $interp = new HTML::Mason::Interp(%params);
    
}

# }}}

# {{{ sub NewApacheHandler 

=head2 NewApacheHandler

  Takes a Mason::Interp object
  Returns a new Mason::ApacheHandler object

=cut

sub NewApacheHandler {
    my $interp=shift;
    my $ah = new HTML::Mason::ApacheHandler (interp=>$interp);
    return($ah);
}

# }}}

package HTML::Mason::Commands;

# {{{ sub Abort
# Error - calls Error and aborts
sub Abort {
    $m->comp("/Elements/Error" , Why => shift);
    $m->abort;
}
# }}}

# {{{ sub LoadTicket - loads a ticket

sub LoadTicket {
    my $id=shift;
    my $CurrentUser = shift;
    my $Ticket = RT::Ticket->new($CurrentUser);
    unless ($Ticket->Load($id)) {
	Abort("Could not load ticket $id");
    }
    return $Ticket;
}
# }}}


# {{{ sub LinkUpIfRequested

sub LinkUpIfRequested {
    my %args=@_;
    if (my $l=$args{ARGS}->{'Link'}) {
	# There is some redundant information from the forms now - we'll
	# ignore one bit of it:
	
	my $luris=$args{ARGS}->{'LinkTo'} || $args{ARGS}->{'LinkFrom'};
	my $ltyp=$args{ARGS}->{'LinkType'};
	if (ref $ltyp) {
	    &mc_comp("/Elements/Error" , Why => "Parameter error");
	    $m->abort;
	}
	for my $luri (split (/ /,$luris)) {
	    my ($LinkId, $Message);
	    if ($l eq 'LinkTo') {
		($LinkId,$Message)=$args{Ticket}->AddLink(Target=>$luri, Type=>$ltyp);
	    } elsif ($l eq 'LinkFrom') {
		($LinkId,$Message)=$args{Ticket}->AddLink(Base=>$luri, Type=>$ltyp);
	    } else {
		&mc_comp("/Elements/Error" , Why => "Parameter error");
		$m->abort;
	    }
	    
	    push(@{$args{Actions}}, $Message);
	}
    }
}

# }}}

# {{{ sub ProcessSimpleActions

## TODO: This is obscenely hacky, that eval should go away.  Eventually,
## the eval is not needed in perl 5.6.0.  Eventually the sub should
## accept more than one Action, and it should handle Actions with
## arguments.
sub ProcessSimpleActions {
    my %args=@_;
    # TODO: What if there are more Actions?
    if (exists $args{ARGS}->{Action}) {
	my ($action)=$args{ARGS}->{Action} =~ /^(Steal|Kill|Take|SetTold)$/;
	my ($res, $msg)=eval('$args{Ticket}->'.$action);
	push(@{$args{Actions}}, $msg);
    }
}

# }}}

# {{{ sub ProcessOwnerChanges

sub ProcessOwnerChanges {
    my %args=@_;
    if ($args{ARGS}->{'SetOwner'}
        and ($args{ARGS}->{'SetOwner'} ne $args{Ticket}->OwnerObj->Id())) {
	my ($Transaction, $Description)=$args{Ticket}->SetOwner($args{ARGS}->{'SetOwner'});
	push(@{$args{Actions}}, $Description);
    }
}
# }}}

# {{{ sub ProcessUpdateMessage
sub ProcessUpdateMessage {
    my %args=@_;
    if ($args{ARGS}->{'UpdateContent'}) {
	my @UpdateContent = split(/\r/,$args{ARGS}->{'UpdateContent'}."\n");
	my $Message = MIME::Entity->build 
	    ( Subject => $args{ARGS}->{'UpdateSubject'} || "",
	    	      Data => \@UpdateContent);
	
	## TODO: Implement public comments
	if ($args{ARGS}->{'UpdateType'} =~ /^(private|public)$/) {
	    my ($Transaction, $Description) = $args{Ticket}->Comment
		( CcMessageTo => $args{ARGS}->{'UpdateCc'},
		  BccMessageTo => $args{ARGS}->{'UpdateBcc'},
		  MIMEObj => $Message,
		  TimeTaken => $args{ARGS}->{'UpdateTimeWorked'});
	    push(@{$args{Actions}}, $Description);
	}
	elsif ($args{ARGS}->{'UpdateType'} eq 'response') {
	    my ($Transaction, $Description) = $args{Ticket}->Correspond
		( CcMessageTo => $args{ARGS}->{'UpdateCc'},
		  BccMessageTo => $args{ARGS}->{'UpdateBcc'},
		  MIMEObj => $Message,
		  TimeTaken => $args{ARGS}->{'UpdateTimeWorked'});
	    push(@{$args{Actions}}, $Description);
	}
    }
}
# }}}

# {{{ sub ProcessStatusChanges 

sub ProcessStatusChanges {
    my %args=@_;
    if ($args{ARGS}->{'SetStatus'} and ($args{ARGS}->{'SetStatus'} ne $args{Ticket}->Status())) {
	my ($Transaction, $Description)=$args{Ticket}->SetStatus($args{ARGS}->{'SetStatus'});
	push(@{$args{Actions}}, $Description);
    }
}

# }}}

# {{{ sub ProcessSearchQuery

=head2 ProcessSearchQuery

  Takes a form such as the one filled out in webrt/Search/Elements/PickRestriction and turns it into something that RT::Tickets can understand.

TODO Doc exactly what comes in the paramhash


=cut

sub ProcessSearchQuery {
    my %args=@_;

    ## TODO: The only parameter here is %ARGS.  Maybe it would be
    ## cleaner to load this parameter as $ARGS, and use $ARGS->{...}
    ## instead of $args{ARGS}->{...} ? :)
    
    #Searches are sticky.
    if (defined $session{'tickets'}) {
	# Reset the old search
	$session{'tickets'}->GotoFirstItem;
    } else {
	# Init a new search
	$session{'tickets'} = RT::Tickets->new($session{'CurrentUser'});
    }

    # {{{ Goto next/prev page
    if ($args{ARGS}->{'GotoPage'} eq 'Next') {
	$session{'tickets'}->NextPage;
    }
    elsif ($args{ARGS}->{'GotoPage'} eq 'Prev') {
	$session{'tickets'}->PrevPage;
    }
    # }}}

    # {{{ Deal with limiting the search
    if ($args{ARGS}->{'TicketsSortBy'}) {
	$session{'tickets_sort_by'} = $args{ARGS}->{'TicketsSortBy'};
	$session{'tickets_sort_order'} = $args{ARGS}->{'TicketsSortOrder'};
	$session{'tickets'}->OrderBy ( FIELD => $args{ARGS}->{'TicketsSortBy'},
				       ORDER => $args{ARGS}->{'TicketsSortOrder'});
    }
    # }}}
    
    # {{{ Set the query limit
    if (defined $args{ARGS}->{'RowsPerPage'}) {
	$RT::Logger->debug("limiting to ". 
			   $args{ARGS}->{'RowsPerPage'} . 
			   " rows");

	$session{'tickets_rows_per_page'} = $args{ARGS}->{'RowsPerPage'};
	$session{'tickets'}->RowsPerPage($args{ARGS}->{'RowsPerPage'});
    }
    
    # }}}
    # {{{ Limit owner
    if ($args{ARGS}->{'ValueOfOwner'} ne '' ) {
	$session{'tickets'}->LimitOwner(					
					VALUE => $args{ARGS}->{'ValueOfOwner'},
					OPERATOR => $args{ARGS}->{'OwnerOp'}
				       );
    }
    # }}}
    # {{{ Limit requestor email
    #TODO this doesn't work
    
    if ($args{ARGS}->{'ValueOfRequestor'} ne '') {
	my $alias=$session{'tickets'}->LimitRequestor (
						       VALUE => $args{ARGS}->{'ValueOfRequestor'},
						       OPERATOR =>  $args{ARGS}->{'RequestorOp'},
						      );
	
    }
    # }}}
    # {{{ Limit Queue
    if ($args{ARGS}->{'ValueOfQueue'} ne '') {
	$session{'tickets'}->LimitQueue(
				    VALUE => $args{ARGS}->{'ValueOfQueue'},
				    OPERATOR => $args{ARGS}->{'QueueOp'});
    }
    # }}}
    # {{{ Limit Status
    if ($args{ARGS}->{'ValueOfStatus'} ne '') {
	if ( ref($args{ARGS}->{'ValueOfStatus'}) ) {
	    foreach my $value ( @{ $args{ARGS}->{'ValueOfStatus'} } ) {
		$session{'tickets'}->LimitStatus (
						  VALUE => $value,
						  OPERATOR =>  $args{ARGS}->{'StatusOp'},
						 );
	    }
	} else {
	    $session{'tickets'}->LimitStatus (
					      VALUE => $args{ARGS}->{'ValueOfStatus'},
					      OPERATOR =>  $args{ARGS}->{'StatusOp'},
					     );
	}
	
    }

# }}}
    # {{{ Limit Subject
    if ($args{ARGS}->{'ValueOfSubject'} ne '') {
	$session{'tickets'}->LimitSubject(
					  VALUE =>  $args{ARGS}->{'ValueOfSubject'},
					  OPERATOR => $args{ARGS}->{'SubjectOp'},
					 );
    }

    # }}}    
    # {{{ Limit Content
    if ($args{ARGS}->{'ValueOfContent'} ne '') {
	$session{'tickets'}->Limit(				
				   VALUE =>  $args{ARGS}->{'ValueOfContent'},
				   OPERATOR => $args{ARGS}->{'ContentOp'},
				  );
    }

    # }}}   
    # {{{ Limit KeywordSelects
    foreach my $KeywordSelectId (
	map { /^KeywordSelect(\d+)$/; $1 }
        grep { /^KeywordSelect(\d+)$/; }
          keys %{$args{ARGS}}
    ) {
      my $form = $args{ARGS}->{"KeywordSelect$KeywordSelectId"};
      my $oper = $args{ARGS}->{"KeywordSelectOp$KeywordSelectId"};
      foreach my $KeywordId ( ref($form) ? @{ $form } : ( $form ) ) {
	  if ($KeywordId) {
	      $session{'tickets'}->LimitKeyword(
						KEYWORDSELECT => $KeywordSelectId,
						OPERATOR => $oper,
						KEYWORD => $KeywordId,
					       );
	  }
      }
      
    }

    # }}}

}
# }}}

# {{{ sub Config 
# TODO: This might eventually read the cookies, user configuration
# information from the DB, queue configuration information from the
# DB, etc.

sub Config {
  my $args=shift;
  my $key=shift;
  return $args->{$key} || $RT::WebOptions{$key};
}

# }}}

# {{{ sub ProcessACLChanges

sub ProcessACLChanges {
    
    my $ACLref= shift;
    my $ARGSref = shift;
    
    my @CheckACL = @$ACLref;
    my %ARGS = %$ARGSref;
    
    my ($ACL, @results);
    foreach $ACL (@CheckACL) {
	
	my ($Principal);
	
	# Parse out what we're really talking about. 
	# it would be good to make this code generic enough to apply
	# to system rights too
	
	if ($ACL =~ /^(.*?)-(\d+)-(.*?)-(\d+)/) {
	    my $PrincipalType = $1;
	    my $PrincipalId = $2;
	    my $Scope = $3;
	    my $AppliesTo = $4;
	    
	    # {{{ Create an object called Principal
	    # so we can do rights operations
	    
	    if ($PrincipalType  eq 'User' ) {
		$Principal = new RT::User($session{'CurrentUser'});
	    } elsif ($PrincipalType eq 'Group') {
		$Principal = new RT::Group($session{'CurrentUser'});
	    } else {
		Abort("$PrincipalType unknown principal type")
	    }	
	    
	    $Principal->Load($PrincipalId) ||
	      Abort("$PrincipalType $PrincipalId couldn't be loaded");
	    
	    # }}}
	    
	    # {{{ load up an RT::ACL object with the same current vals of this ACL
	    
	    my $CurrentACL = new RT::ACL($session{'CurrentUser'});
	    if ($Scope eq 'Queue') {
		$CurrentACL->LimitToQueue($AppliesTo);
	    } elsif ($Scope eq 'System') {
		$CurrentACL->LimitToSystem();
	    }
	    
	    $CurrentACL->LimitPrincipalToType($PrincipalType);
	    $CurrentACL->LimitPrincipalToId($PrincipalId);
	    
	    # }}}
	    
	    # {{{ Get the values of the select we're working with 
	    # into an array. it will contain all the new rights that have 
	    # been granted
	    
	    
	    #Hack to turn the ACL returned into an array
	    my @rights = ref($ARGS{"ACL-$ACL"}) eq 'ARRAY' ?
	      @{$ARGS{"ACL-$ACL"}} : ($ARGS{"ACL-$ACL"});
	    
	    # }}}
	    
	    # {{{ Add any rights we need. at the same time, build up
	    # a hash of what rights have been selected 
	    
	    my ($right,%rights);
	    foreach $right (@rights) {
		
		next unless ($right);
		
		$RT::Logger->debug ("Now handling right $right\n");
		
		
		#if the right that's been selected wasn't there before, add it.
		unless ($CurrentACL->HasEntry(RightScope => "$Scope",
					      RightName => "$right",
					      RightAppliesTo => "$AppliesTo", 
					      PrincipalType => $PrincipalType ,
					      PrincipalId => $Principal->Id )) {
		    
		    #Add new entry to list of rights.
		    $RT::Logger->debug("Granting queue $AppliesTo right $right to ".
				       $Principal->id.	 " for queue $AppliesTo\n"); 
		    if ($Scope eq 'Queue') {
			my ($val, $msg) = $Principal->GrantQueueRight( RightAppliesTo => $AppliesTo,
								       RightName => "$right" );

			if ($val) { 
			    push (@results, "Granted right $right to ".
				  $Principal->id." for queue $AppliesTo.\n");
			}
			else {
			    push (@results, $msg);
			}
		    }
		    elsif ($Scope eq 'System') {
			my ($val, $msg)	=$Principal->GrantSystemRight( RightAppliesTo => $AppliesTo,
								       RightName => "$right" );
			if ($val) {
			    push (@results, "Granted system right '$right' to ".
				  $Principal->id. ".\n");	 
			}
			else {
				push (@results, $msg);
			    }	
		    }
		}
		# Build up a hash of rights, so that we can easily check
		# to make sure the user has not turned off any rights.
		
		$rights{"$right"} = 1;
		
	    }
	    # }}}
	    
	    # {{{ remove any rights that have been deleted
	    while ($right = $CurrentACL->Next()) {
		#If @rights doesn't contain what $entry does, then the user has
		# removed that right.
		
		unless ($rights{$right->RightName}) {
		    #yank the entry out of  the ACL
		    $right->Delete();
		    push (@results, "Revoked ".$right->PrincipalType." ".
                    $right->PrincipalId . "'s right to ". $right->RightName. 
                    "  for " . $right->RightScope. " ". 
                    $right->RightAppliesTo.".\n");
		}
		
		
	    }
	    # }}}
	    
	    
	}
    }
    
    return (@results);
}

# }}}

1;
