package SIMP::Collector::TSDSPusher;

use strict;
use warnings;

use Moo;
use JSON::XS qw(encode_json);
use Data::Dumper;

use SIMP::Collector;
use GRNOC::WebService::Client;

use constant MAX_TSDS_MESSAGES => 20;
use constant SERVICE_CACHE_FILE => "/etc/grnoc/name-service-cacher/name-service.xml";

has logger => (is => 'rwp',
	       required => 1);

has worker_name => (is => 'ro',
		    required => 1);

has tsds_config => (is => 'rwp',
		    required => 1);

has tsds_svc => (is => 'rwp');

sub BUILD {
    my ($self) = @_;

    # Set up our TSDS webservice object when construcuted
    $self->_set_tsds_svc(GRNOC::WebService::Client->new(
			     url => $self->tsds_config->{'url'},
			     # urn => $self->tsds_config->{'urn'},
			     uid => $self->tsds_config->{'user'},
			     passwd => $self->tsds_config->{'password'},
			     # realm => $self->tsds_config->{'realm'},
			     # service_cache_file => SERVICE_CACHE_FILE,
			     usePost => 1
			 ));
}

sub push {
    my ($self, $msg_list) = @_;

    # Push messages to TSDS in MAX_TSDS_MESSAGES chunks
    if (scalar @$msg_list > 0) {
	my @msgs = splice(@$msg_list, 0, MAX_TSDS_MESSAGES);
	$self->logger->info($self->worker_name . " Pushing " . scalar @msgs . " messages to TSDS");
	my $res = $self->tsds_svc->add_data(
	    data => encode_json(\@msgs)
	);
	if (!defined($res) || $res->{'error'}) {
	    $self->logger->error($self->worker_name . " Error pushing data to TSDS: " . SIMP::Collector::error_message($res));
	}
	return 1;
    }
    $self->logger->info($self->worker_name . " Nothing to push to TSDS");
    return;
}

1;
