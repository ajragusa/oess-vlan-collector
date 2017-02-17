package GRNOC::OESS::Collector::Master;

use strict;
use warnings;

use Moo;
use Types::Standard qw(Str Bool);
use Proc::Daemon;
use Parallel::ForkManager;
use Data::Dumper; 

use GRNOC::Config;
use GRNOC::RabbitMQ::Client;
use GRNOC::OESS::Collector::Worker;

has config_file => (is => 'ro', isa => Str, required => 1);
has pidfile => (is => 'ro', isa => Str, required => 1);
has daemonize => (is => 'ro', isa => Bool, required => 1);

has logger => (is => 'rwp');
has simp_config => (is => 'rwp');
has tsds_config => (is => 'rwp');
has hosts => (is => 'rwp', default => sub { [] });
has interval => (is => 'rwp');
has composite_name => (is => 'rwp');
has workers => (is => 'rwp');

sub BUILD {
    my $self = shift;

    $self->_set_logger(GRNOC::Log->get_logger());

    return $self;
}

sub start {
    my ($self) = @_;
    
    $self->logger->info('Starting.');
    $self->logger->debug('Setting up signal handlers.');

    $SIG{'TERM'} = sub {
	$self->logger->info('Received SIGTERM.');
	$self->stop();
    };

    $SIG{'HUP'} = sub {
	$self->logger->info('Received SIGHUP.');
    };

    if ($self->daemonize) {
	$self->logger->debug('Daemonizing.');

	my $daemon = Proc::Daemon->new(pid_file => $self->pidfile);
	my $pid = $daemon->Init();

	if ($pid) {
	    sleep 1;
	    die 'Spawning child process failed' if !$daemon->Status();
	    exit(0);
	}
    }

    $self->_load_config();

    $self->_create_workers();
}

sub _load_config {
    my ($self) = @_;

    $self->logger->info("Reading configuration from $self->config_file");

    my $conf = GRNOC::Config->new(config_file => $self->config_file,
				       force_array => 1);

    $self->_set_simp_config($conf->get('/config/simp')->[0]);

    $self->_set_tsds_config($conf->get('/config/tsds')->[0]);
    
    my @hosts;
    foreach my $host (@{$conf->get('/config/hosts/host')}) {
	push @hosts, $host if defined($host);
    }
    $self->_set_hosts(\@hosts);

    $self->_set_interval($conf->get('/config/collection/@interval')->[0]);

    $self->_set_composite_name($conf->get('/config/collection/@composite-name')->[0]);

    $self->_set_workers($conf->get('/config/@workers')->[0]);

}

sub _create_workers {
    my ($self) = @_;

    my $forker = Parallel::ForkManager->new($self->workers);

    for (my $worker_id=0; $worker_id<$self->workers; $worker_id++) {
	$forker->start() and next;
	
	my $worker = GRNOC::OESS::Collector::Worker->new( logger => $self->logger,
							  composite_name => $self->composite_name,
							  hosts => $self->hosts,
							  simp_config => $self->simp_config,
							  tsds_config => $self->tsds_config,
							  interval => $self->interval,
							  workers => $self->workers
	    );

	$worker->run();
    
	$forker->finish();
    }

    $forker->wait_all_children();
}
    
1;