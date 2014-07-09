//
//  twilio_config.m
//  TwilioSDK
//
//  Created by Rob Simutis on 2/2/12.
//  Copyright (c) 2012 Twilio. All rights reserved.
//

#import "twilio_config.h"
#import <pjsua-lib/pjsua.h>


void twilio_transport_config_defaults(twilio_transport_config* config)
{
	bzero(config, sizeof(twilio_transport_config));
	config->sip_transport_type = TRANSPORT_TYPE_TLS;
}

void twilio_media_config_defaults(twilio_media_config* config)
{
	bzero(config, sizeof(twilio_media_config));
	config->voice_quality = 6; // match the flash impl
	config->vad_enabled = 0; // turn off voice-activity-detection.  this gate is pretty aggressive
	// and causes perceived stuttering as it tries to filter out noise.
	// This is not ideal, however...need a better algorithm here than
	// what's in the pjsip stack.
	config->echo_cancellation_tail_ms = PJSUA_DEFAULT_EC_TAIL_LEN;
	
	config->sound_record_latency_ms = PJMEDIA_SND_DEFAULT_REC_LATENCY;
	config->sound_playback_latency_ms = PJMEDIA_SND_DEFAULT_PLAY_LATENCY;
}

void twilio_logging_config_defaults(twilio_logging_config* config)
{
	bzero(config, sizeof(twilio_logging_config));
}

void twilio_config_defaults(twilio_config* config)
{
	bzero(config, sizeof(twilio_config));
	
	twilio_transport_config_defaults(&config->transport_config);
	twilio_media_config_defaults(&config->media_config);
	twilio_logging_config_defaults(&config->log_config);
}

void twilio_config_copy(twilio_config* target, const twilio_config* source)
{
	// for now it's a simple memcpy
	memcpy(target, source, sizeof(twilio_config));
}
