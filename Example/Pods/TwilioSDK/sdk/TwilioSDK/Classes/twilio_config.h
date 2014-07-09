//
//  twilio_config.h
//  TwilioSDK
//
//  Created by Rob Simutis on 2/2/12.
//  Copyright (c) 2012 Twilio. All rights reserved.
//

#define TRANSPORT_TYPE_UDP 0
#define TRANSPORT_TYPE_TCP 1
#define TRANSPORT_TYPE_TLS 2

typedef struct twilio_transport_config
{
	unsigned int sip_transport_type; // TRANSPORT_TYPE_ values
} twilio_transport_config;

typedef struct twilio_media_config
{
	unsigned int vad_enabled; // 0 or 1
	unsigned int voice_quality; // 0 - 10
	unsigned int echo_cancellation_tail_ms;
	unsigned int sound_record_latency_ms;
	unsigned int sound_playback_latency_ms;
} twilio_media_config;

typedef struct twilio_logging_config
{
	NSString* logFileOutput;
} twilio_logging_config;

typedef struct twilio_config
{
	twilio_transport_config transport_config;
	twilio_media_config media_config;
	twilio_logging_config log_config;
} twilio_config;


void twilio_transport_config_defaults(twilio_transport_config* config);
void twilio_media_config_defaults(twilio_media_config* config);
void twilio_logging_config_defaults(twilio_logging_config* config);
void twilio_config_defaults(twilio_config* config);
void twilio_config_copy(twilio_config* target, const twilio_config* source);

