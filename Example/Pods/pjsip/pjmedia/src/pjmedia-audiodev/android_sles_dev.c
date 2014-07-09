/*
 * Copyright (C) 2011 Dan Arrhenius <dan@keystream.se>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */
#include <pjmedia_audiodev.h>
#include <pj/assert.h>
#include <pj/log.h>
#include <pj/os.h>
#include <pj/pool.h>
#include <pjmedia/errno.h>

#if defined(PJMEDIA_AUDIO_DEV_HAS_ANDROID_SLES)

#include <SLES/OpenSLES.h>
#include <SLES/OpenSLES_Android.h>
#include <SLES/OpenSLES_AndroidConfiguration.h>

#include "android_sles_dev.h"

/*
  Android NDK revision 5b has a buggy SLES/OpenSLES_AndroidConfiguration.h
  Check if the macros are defined.
 */
#ifndef SL_ANDROID_KEY_STREAM_TYPE
#define SL_ANDROID_KEY_STREAM_TYPE ((const SLchar*)"androidPlaybackStreamType")
#endif
#ifndef SL_ANDROID_STREAM_VOICE
#define SL_ANDROID_STREAM_VOICE ((SLuint32)0x00000000)
#endif
#ifndef SL_ANDROID_STREAM_MEDIA
#define SL_ANDROID_STREAM_MEDIA ((SLint32)0x00000003)
#endif
#ifndef SL_ANDROID_KEY_RECORDING_PRESET
#define SL_ANDROID_KEY_RECORDING_PRESET ((const SLchar*)"androidRecordingPreset")
#endif
#ifndef SL_ANDROID_RECORDING_PRESET_GENERIC
#define SL_ANDROID_RECORDING_PRESET_GENERIC ((SLuint32)0x00000001)
#endif


#define THIS_FILE "android_sles_dev.c"

struct sles_factory
{
    pjmedia_aud_dev_factory  base;
    pj_pool_factory         *pf;
    pj_pool_t               *pool;
    pjmedia_aud_dev_info     dev_info;

    sles_lib_ptr_table_t ptr_table;
    SLObjectItf  e_obj;
    SLEngineItf  e_engine;

    pj_bool_t device_has_hw_ec;
};


struct sles_stream {
    pjmedia_aud_stream base;
    struct sles_factory* f;

    // common
    pj_pool_t   *pool;
    void        *user_data;
    pjmedia_aud_param param;

    // rec
    pjmedia_aud_play_cb rec_cb;
    pj_thread_desc  r_thread_desc;
    pj_thread_t    *r_thread;
    SLObjectItf     r_obj;
    SLRecordItf     r_rec;
    SLAndroidSimpleBufferQueueItf r_buf_queue;
    u_int16_t     **r_buf;
    unsigned        r_num_buffers;
    unsigned        r_buf_index;
    unsigned        r_buf_size;
    pj_timestamp    r_tstamp;

    // play
    pjmedia_aud_play_cb play_cb;
    pj_thread_desc  p_thread_desc;
    pj_thread_t    *p_thread;
    SLObjectItf     mix_obj;
    SLObjectItf     p_obj;
    SLPlayItf       p_play;
    SLAndroidSimpleBufferQueueItf p_buf_queue;
    u_int16_t     **p_buf;
    unsigned        p_num_buffers;
    unsigned        p_buf_index;
    unsigned        p_buf_size;
    pj_timestamp    p_tstamp;
};


static pj_status_t check_hardware_ec(struct sles_factory *f);

/*
 * Factory prototypes
 */
static pj_status_t sles_factory_init(pjmedia_aud_dev_factory *f);
static pj_status_t sles_factory_destroy(pjmedia_aud_dev_factory *f);
static unsigned    sles_factory_get_dev_count(pjmedia_aud_dev_factory *f);
static pj_status_t sles_factory_get_dev_info(pjmedia_aud_dev_factory *f,
                                             unsigned index,
                                             pjmedia_aud_dev_info *info);
static pj_status_t sles_factory_default_param(pjmedia_aud_dev_factory *f,
                                              unsigned index,
                                              pjmedia_aud_param *param);
static pj_status_t sles_factory_create_stream(pjmedia_aud_dev_factory *f,
                                              const pjmedia_aud_param *param,
                                              pjmedia_aud_rec_cb rec_cb,
                                              pjmedia_aud_play_cb play_cb,
                                              void *user_data,
                                              pjmedia_aud_stream **p_strm);

/*
 * Stream prototypes
 */
static pj_status_t sles_stream_get_param(pjmedia_aud_stream *s,
                                         pjmedia_aud_param *param);
static pj_status_t sles_stream_get_cap(pjmedia_aud_stream *s,
                                       pjmedia_aud_dev_cap cap,
                                       void *value);
static pj_status_t sles_stream_set_cap(pjmedia_aud_stream *s,
                                       pjmedia_aud_dev_cap cap,
                                       const void *value);
static pj_status_t sles_stream_start(pjmedia_aud_stream *s);
static pj_status_t sles_stream_stop(pjmedia_aud_stream *s);
static pj_status_t sles_stream_destroy(pjmedia_aud_stream *s);


static pjmedia_aud_dev_factory_op sles_factory_op =
{
    &sles_factory_init,
    &sles_factory_destroy,
    &sles_factory_get_dev_count,
    &sles_factory_get_dev_info,
    &sles_factory_default_param,
    &sles_factory_create_stream
};

static pjmedia_aud_stream_op sles_stream_op =
{
    &sles_stream_get_param,
    &sles_stream_get_cap,
    &sles_stream_set_cap,
    &sles_stream_start,
    &sles_stream_stop,
    &sles_stream_destroy
};


static void destroy_sles_audio (struct sles_stream *stream)
{
    // destroy the player
    //
    if (stream->p_obj)
        (*stream->p_obj)->Destroy (stream->p_obj);
    stream->p_obj = NULL;

    // destroy the recorder
    //
    if (stream->r_obj)
        (*stream->r_obj)->Destroy (stream->r_obj);
    stream->r_obj = NULL;

    // destroy the output mixer
    //
    if (stream->mix_obj)
        (*stream->mix_obj)->Destroy (stream->mix_obj);
    stream->mix_obj = NULL;
}


static pj_status_t create_engine (struct sles_factory *sf)
{
    SLresult result;

    PJ_ASSERT_RETURN (sf!=NULL, PJ_EINVAL);

    if (sf->e_obj)
        return PJ_SUCCESS; // Engine alreay created.

    // Create the audio engine
    //
    result = sf->ptr_table.slCreateEngine (&sf->e_obj, 0, NULL, 0, NULL, NULL);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error: Unable to create the audio engine"));
        sf->e_obj = NULL;
        return PJ_ENOMEM;
    }

    // Realize the audio engine
    //
    result = (*sf->e_obj)->Realize (sf->e_obj, SL_BOOLEAN_FALSE);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error: Unable to realize the audio engine"));
        (*sf->e_obj)->Destroy (sf->e_obj);
        sf->e_obj = NULL;
        return PJ_EUNKNOWN;
    }

    // Get the engine interface
    //
    result = (*sf->e_obj)->GetInterface (sf->e_obj, *(sf->ptr_table.SL_IID_ENGINE), &sf->e_engine);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error: Unable to get the audio engine interface"));
        (*sf->e_obj)->Destroy (sf->e_obj);
        sf->e_obj = NULL;
        return PJ_EUNKNOWN;
    }

    return PJ_SUCCESS;
}


pjmedia_aud_dev_factory *pjmedia_android_sles_factory(pj_pool_factory *pf,
                                                      sles_lib_ptr_table_t *sles_lib_ptr_table)
{
    struct sles_factory *sf;
    pj_pool_t *pool;

    pool = pj_pool_create(pf, "sles_aud", 256, 256, NULL);
    sf = PJ_POOL_ZALLOC_T(pool, struct sles_factory);
    sf->pf = pf;
    sf->pool = pool;
    sf->ptr_table = *sles_lib_ptr_table;
    sf->base.op = &sles_factory_op;

    return &sf->base;
}


static pj_status_t sles_factory_init(pjmedia_aud_dev_factory *f)
{
    pj_status_t status;
    struct sles_factory *sf = (struct sles_factory*)f;
    PJ_ASSERT_RETURN(sf!=NULL, PJ_EINVAL);

    // Initialize device info
    //
    pj_bzero (&sf->dev_info, sizeof(sf->dev_info));
    strcpy (sf->dev_info.driver, "Android OpenSL-ES");
    strcpy (sf->dev_info.name, "SLES");
    sf->dev_info.output_count = 2;
    sf->dev_info.input_count  = 1;
    sf->dev_info.default_samples_per_sec = 16000;

    // Create the audio engine
    status = create_engine (sf);
    if (status != PJ_SUCCESS) {
        return status;
    }

    check_hardware_ec(sf);

    return PJ_SUCCESS;
}


static pj_status_t sles_factory_destroy(pjmedia_aud_dev_factory *f)
{
    struct sles_factory *sf = (struct sles_factory*)f;
    PJ_ASSERT_RETURN (sf!=NULL, PJ_EINVAL);

    // Destroy the audio engine
    if (sf->e_obj) {
        (*sf->e_obj)->Destroy (sf->e_obj);
        sf->e_obj = NULL;
    }

    if (sf->pool) {
        pj_pool_t *pool = sf->pool;
        sf->pool = NULL;
        pj_pool_release (pool);
    }

    return PJ_SUCCESS;
}


static unsigned sles_factory_get_dev_count(pjmedia_aud_dev_factory *f)
{
    return 1;
}


static pj_status_t sles_factory_get_dev_info(pjmedia_aud_dev_factory *f,
                                             unsigned index,
                                             pjmedia_aud_dev_info *info)
{
    struct sles_factory *sf = (struct sles_factory*) f;

    PJ_ASSERT_RETURN(index==0 && sf, PJ_EINVAL);

    pj_memcpy (info, &sf->dev_info, sizeof(*info));
    info->caps =
        PJMEDIA_AUD_DEV_CAP_INPUT_LATENCY  |
        PJMEDIA_AUD_DEV_CAP_OUTPUT_LATENCY |
        PJMEDIA_AUD_DEV_CAP_OUTPUT_ROUTE;

    if (sf->device_has_hw_ec)
        info->caps |= PJMEDIA_AUD_DEV_CAP_EC;

    return PJ_SUCCESS;
}


static pj_status_t sles_factory_default_param(pjmedia_aud_dev_factory *f,
                                              unsigned index,
                                              pjmedia_aud_param *param)
{
    struct sles_factory *sf = (struct sles_factory*) f;

    PJ_ASSERT_RETURN(index==0 && sf, PJ_EINVAL);

    pj_bzero (param, sizeof(*param));
    param->dir               = PJMEDIA_DIR_CAPTURE_PLAYBACK;
    param->rec_id            = 0;
    param->play_id           = 0;
    param->clock_rate        = sf->dev_info.default_samples_per_sec;
    param->channel_count     = 1;
    param->samples_per_frame = param->clock_rate * 20 / 1000;
    param->bits_per_sample   = 16;
    param->flags             = sf->dev_info.caps;
    param->input_latency_ms  = PJMEDIA_SND_DEFAULT_REC_LATENCY;
    param->output_latency_ms = PJMEDIA_SND_DEFAULT_PLAY_LATENCY;
    param->ec_enabled        = sf->device_has_hw_ec;
    return PJ_SUCCESS;
}


static pj_status_t allocate_buffers (struct sles_stream* stream)
{
    pjmedia_aud_param *param = &stream->param;
    unsigned frame_time;
    unsigned latency;
    unsigned i;

    if (param->dir & PJMEDIA_DIR_PLAYBACK) {
        // Get the configured latency
        if (param->flags & PJMEDIA_AUD_DEV_CAP_OUTPUT_LATENCY)
            latency = param->output_latency_ms;
        else
            latency = PJMEDIA_SND_DEFAULT_PLAY_LATENCY;

        // Get the buffer size
        stream->p_buf_size =
            param->samples_per_frame *
            param->channel_count     *
            param->bits_per_sample   / 8;

        // Get the frame time
        frame_time = param->samples_per_frame * 1000 / param->clock_rate;

        // Get the number of buffers and set the actual latency
        stream->p_num_buffers = latency / frame_time;
        pj_assert (stream->p_num_buffers > 0);
        param->output_latency_ms = stream->p_num_buffers * frame_time;

        // Allocate buffers
        stream->p_buf = pj_pool_alloc (stream->pool, stream->p_num_buffers * sizeof(u_int16_t*));
        if (stream->p_buf == NULL)
            return PJ_ENOMEM;
        for (i=0; i<stream->p_num_buffers; i++) {
            stream->p_buf[i] = pj_pool_alloc (stream->pool, stream->p_buf_size);
            if (stream->p_buf[i] == NULL)
                return PJ_ENOMEM;
        }

        stream->p_buf_index = 0;
    }

    if (param->dir & PJMEDIA_DIR_CAPTURE) {
        // Get the configured latency
        if (param->flags & PJMEDIA_AUD_DEV_CAP_INPUT_LATENCY)
            latency = param->input_latency_ms;
        else
            latency = PJMEDIA_SND_DEFAULT_REC_LATENCY;

        // Get the buffer size
        stream->r_buf_size =
            param->samples_per_frame *
            param->channel_count     *
            param->bits_per_sample   / 8;

        // Get the frame time
        frame_time = param->samples_per_frame * 1000 / param->clock_rate;

        // Get the number of buffers and set the actual latency
        stream->r_num_buffers = latency / frame_time;
        pj_assert (stream->r_num_buffers > 0);
        param->output_latency_ms = stream->r_num_buffers * frame_time;

        // Allocate buffers
        stream->r_buf = pj_pool_alloc (stream->pool, stream->r_num_buffers * sizeof(u_int16_t*));
        if (stream->r_buf == NULL)
            return PJ_ENOMEM;
        for (i=0; i<stream->r_num_buffers; i++) {
            stream->r_buf[i] = pj_pool_alloc (stream->pool, stream->r_buf_size);
            if (stream->r_buf[i] == NULL)
                return PJ_ENOMEM;
        }

        stream->r_buf_index = 0;
    }

    return PJ_SUCCESS;
}


static void play_callback (SLAndroidSimpleBufferQueueItf buf_queue, void* context)
{
    pj_status_t status;
    SLresult result;
    struct sles_stream* stream = (struct sles_stream*) context;
    pjmedia_frame frame;

    frame.type          = PJMEDIA_FRAME_TYPE_AUDIO;
    frame.buf           = stream->p_buf[stream->p_buf_index];
    frame.size          = stream->p_buf_size;
    frame.timestamp.u64 = stream->p_tstamp.u64;
    frame.bit_info      = 0;

    if (!pj_thread_is_registered())
        pj_thread_register ("sles_play", stream->p_thread_desc, &stream->p_thread);

    status = stream->play_cb (stream->user_data, &frame);
    if (status != PJ_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Play callback failed!"));
        pj_bzero (stream->p_buf[stream->p_buf_index], stream->p_buf_size);
    }

    if (frame.type != PJMEDIA_FRAME_TYPE_AUDIO)
        pj_bzero (stream->p_buf[stream->p_buf_index], stream->p_buf_size);

    result = (*stream->p_buf_queue)->Enqueue (stream->p_buf_queue,
                                              stream->p_buf[stream->p_buf_index],
                                              stream->p_buf_size);
    if (result != SL_RESULT_SUCCESS)
        PJ_LOG (2,(THIS_FILE, "Unable to queue play buffer"));

    stream->p_tstamp.u64 += stream->param.samples_per_frame;

    stream->p_buf_index++;
    if (stream->p_buf_index >= stream->p_num_buffers)
        stream->p_buf_index = 0;
}


static void rec_callback (SLAndroidSimpleBufferQueueItf buf_queue, void* context)
{
    pj_status_t status;
    SLresult result;
    struct sles_stream* stream = (struct sles_stream*) context;
    pjmedia_frame frame;

    frame.type          = PJMEDIA_FRAME_TYPE_AUDIO;
    frame.buf           = stream->r_buf[stream->r_buf_index];
    frame.size          = stream->r_buf_size;
    frame.timestamp.u64 = stream->r_tstamp.u64;
    frame.bit_info      = 0;

    if (!pj_thread_is_registered())
        pj_thread_register ("sles_rec", stream->r_thread_desc, &stream->r_thread);

    status = stream->rec_cb (stream->user_data, &frame);
    if (status != PJ_SUCCESS)
        PJ_LOG (2,(THIS_FILE, "Rec callback failed!"));

    stream->r_tstamp.u64 += stream->param.samples_per_frame;

    result = (*stream->r_buf_queue)->Enqueue (stream->r_buf_queue,
                                              stream->r_buf[stream->r_buf_index],
                                              stream->r_buf_size);
    if (result != SL_RESULT_SUCCESS)
        PJ_LOG (2,(THIS_FILE, "Unable to queue rec buffer"));

    stream->r_buf_index++;
    if (stream->r_buf_index >= stream->r_num_buffers)
        stream->r_buf_index = 0;
}


static pj_status_t open_play (struct sles_stream* stream)
{
    SLresult result;
    struct sles_factory* f = stream->f;
    // Audio player parameters
    const SLInterfaceID id[2] = {*(f->ptr_table.SL_IID_ANDROIDSIMPLEBUFFERQUEUE), *(f->ptr_table.SL_IID_ANDROIDCONFIGURATION)};
    const SLboolean req[2] = {SL_BOOLEAN_TRUE, SL_BOOLEAN_TRUE};
    // Player configuration
    SLint32 play_type;
    SLAndroidConfigurationItf play_config;
    // Audio source
    SLDataLocator_AndroidSimpleBufferQueue loc_bq = {SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE,
                                                     stream->p_num_buffers};
    SLDataFormat_PCM format_pcm;
    SLDataSource audio_src = {&loc_bq, &format_pcm};
    // Audio sink
    SLDataLocator_OutputMix loc_outmix;
    SLDataSink audio_sink = {&loc_outmix, NULL};

    // Set the audio route
    if (stream->param.output_route == PJMEDIA_AUD_DEV_ROUTE_LOUDSPEAKER)
        play_type = SL_ANDROID_STREAM_MEDIA;
    else
        play_type = SL_ANDROID_STREAM_VOICE;

    // Create the output mixer
    result = (*f->e_engine)->CreateOutputMix (f->e_engine, &stream->mix_obj, 0, NULL, NULL);
    if (result != SL_RESULT_SUCCESS) {        
        PJ_LOG (2,(THIS_FILE, "Error creating the audio output mixer"));
        return PJ_ENOMEM;
    }

    // Realize the output mixer
    result = (*stream->mix_obj)->Realize (stream->mix_obj, SL_BOOLEAN_FALSE);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error realizing the audio output mixer"));
        return PJ_EUNKNOWN;
    }

    // Create the audio player object
    format_pcm.formatType    = SL_DATAFORMAT_PCM;
    format_pcm.numChannels   = (SLuint32) stream->param.channel_count;
    format_pcm.samplesPerSec = (SLuint32) stream->param.clock_rate * 1000;
    format_pcm.bitsPerSample = (SLuint32) stream->param.bits_per_sample;
    format_pcm.containerSize = (SLuint32) stream->param.bits_per_sample;
    format_pcm.channelMask   = SL_SPEAKER_FRONT_CENTER;
    format_pcm.endianness    = SL_BYTEORDER_LITTLEENDIAN;
    loc_outmix.locatorType = SL_DATALOCATOR_OUTPUTMIX;
    loc_outmix.outputMix   = stream->mix_obj;
    result = (*f->e_engine)->CreateAudioPlayer (f->e_engine,
                                                &stream->p_obj,
                                                &audio_src,
                                                &audio_sink,
                                                2,
                                                id,
                                                req);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error creating the audio player"));
        return PJ_ENOMEM;
    }

    // Configure the audio player
    result = (*stream->p_obj)->GetInterface (stream->p_obj,
                                             *(f->ptr_table.SL_IID_ANDROIDCONFIGURATION),
                                             &play_config);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error getting the player configuration interface"));
        return PJ_EUNKNOWN;
    }
    (*play_config)->SetConfiguration (play_config,
                                      SL_ANDROID_KEY_STREAM_TYPE,
                                      &play_type,
                                      sizeof(play_type));

    // Realize the audio player
    result = (*stream->p_obj)->Realize (stream->p_obj, SL_BOOLEAN_FALSE);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Unable to realize the audio player object"));
        return PJ_EUNKNOWN;
    }

    // Get the audio player interface
    result = (*stream->p_obj)->GetInterface (stream->p_obj, *(f->ptr_table.SL_IID_PLAY), &stream->p_play);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error getting the audio player interface"));
        return PJ_EUNKNOWN;
    }

    // Get the audio buffer queue interface
    result = (*stream->p_obj)->GetInterface (stream->p_obj,
                                             *(f->ptr_table.SL_IID_ANDROIDSIMPLEBUFFERQUEUE),
                                             &stream->p_buf_queue);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error getting the audio playback buffer queue"));
        return PJ_EUNKNOWN;
    }

    // Register the buffer queue callback
    result = (*stream->p_buf_queue)->RegisterCallback (stream->p_buf_queue, play_callback, stream);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error registering the play queue callback"));
        return PJ_EUNKNOWN;
    }

    return PJ_SUCCESS;
}

// separate this out so we can do a quick check to see if
// hardware echo cancellation is supported
static pj_status_t create_configure_recorder(struct sles_stream *stream, pj_bool_t *hw_ec_supported)
{
    SLresult result;
    struct sles_factory* f = stream->f;
    // Audio recorder parameters
    const SLInterfaceID id[2] = {*(f->ptr_table.SL_IID_ANDROIDSIMPLEBUFFERQUEUE), *(f->ptr_table.SL_IID_ANDROIDCONFIGURATION)};
    const SLboolean req[2] = {SL_BOOLEAN_TRUE, SL_BOOLEAN_TRUE};
    // Record configuration
    // API level 14 and above supports VOICE_COMMUNICATION, which will enable
    // hardware echo cancellation.  we autodetect which is supported on startup.
    SLint32 rec_type = SL_ANDROID_RECORDING_PRESET_GENERIC;
    SLAndroidConfigurationItf rec_config;
    // Audio source
    SLDataLocator_IODevice loc_dev = {SL_DATALOCATOR_IODEVICE,
                                      SL_IODEVICE_AUDIOINPUT,
                                      SL_DEFAULTDEVICEID_AUDIOINPUT,
                                      NULL};
    SLDataSource audio_src = {&loc_dev, NULL};
    // Audio sink
    SLDataLocator_AndroidSimpleBufferQueue loc_bq = {SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE,
                                                     stream->r_num_buffers};
    SLDataFormat_PCM format_pcm;
    SLDataSink audio_sink = {&loc_bq, &format_pcm};

    // Create the audio recorder object
    format_pcm.formatType    = SL_DATAFORMAT_PCM;
    format_pcm.numChannels   = (SLuint32) stream->param.channel_count;
    format_pcm.samplesPerSec = (SLuint32) stream->param.clock_rate * 1000;
    format_pcm.bitsPerSample = (SLuint32) stream->param.bits_per_sample;
    format_pcm.containerSize = (SLuint32) stream->param.bits_per_sample;
    format_pcm.channelMask   = SL_SPEAKER_FRONT_CENTER;
    format_pcm.endianness    = SL_BYTEORDER_LITTLEENDIAN;
    result = (*f->e_engine)->CreateAudioRecorder (f->e_engine,
                                                  &stream->r_obj,
                                                  &audio_src,
                                                  &audio_sink,
                                                  2,
                                                  id,
                                                  req);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error creating the audio recorder"));
        return PJ_ENOMEM;
    }

    // Configure the recorder
    result = (*stream->r_obj)->GetInterface (stream->r_obj, *(f->ptr_table.SL_IID_ANDROIDCONFIGURATION), &rec_config);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error getting the recorder configuration interface"));
        return PJ_EUNKNOWN;
    }

    // only try if the stream requests it and if the HW supports it or we're testing the HW
    if (stream->param.ec_enabled && (f->device_has_hw_ec || hw_ec_supported))
        rec_type = SL_ANDROID_RECORDING_PRESET_VOICE_COMMUNICATION;

    result = (*rec_config)->SetConfiguration (rec_config,
                                              SL_ANDROID_KEY_RECORDING_PRESET,
                                              &rec_type,
                                              sizeof(rec_type));
    if (result != SL_RESULT_SUCCESS &&
        rec_type == SL_ANDROID_RECORDING_PRESET_VOICE_COMMUNICATION)
    {
        rec_type = SL_ANDROID_RECORDING_PRESET_GENERIC;
        result = (*rec_config)->SetConfiguration (rec_config,
                                                  SL_ANDROID_KEY_RECORDING_PRESET,
                                                  &rec_type,
                                                  sizeof(rec_type));
    }

    stream->param.ec_enabled = rec_type == SL_ANDROID_RECORDING_PRESET_VOICE_COMMUNICATION;
    PJ_LOG(4,(THIS_FILE, "Set mic recording config to %s",
              stream->param.ec_enabled ? "VOICE_COMMUNICATION"
                                      : (result == SL_RESULT_SUCCESS ? "GENERIC" : "(failed)")));

    if (hw_ec_supported)
        *hw_ec_supported = stream->param.ec_enabled;

    return PJ_SUCCESS;
}

static pj_status_t check_hardware_ec(struct sles_factory *f)
{
    pj_status_t status;
    struct sles_stream stream;

    status = sles_factory_default_param((pjmedia_aud_dev_factory*)f, 0, &stream.param);
    if (status != PJ_SUCCESS)
        return status;

    stream.f = f;
    stream.r_num_buffers = PJMEDIA_SND_DEFAULT_REC_LATENCY / (stream.param.samples_per_frame * 1000 / stream.param.clock_rate);
    stream.param.ec_enabled = PJ_TRUE;

    status = create_configure_recorder(&stream, &f->device_has_hw_ec);
    if (status == PJ_SUCCESS && stream.r_obj)
        (*stream.r_obj)->Destroy(stream.r_obj);

    return status;
}

static pj_status_t open_rec (struct sles_stream* stream)
{
    SLresult result;
    struct sles_factory* f = stream->f;
    pj_status_t status;

    status = create_configure_recorder(stream, NULL);
    if (status != PJ_SUCCESS)
        return status;

    // Realize the recorder
    result = (*stream->r_obj)->Realize (stream->r_obj, SL_BOOLEAN_FALSE);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error realizing the audio recorder"));
        return PJ_ENOMEM;
    }

    // Get the recorder interface
    result = (*stream->r_obj)->GetInterface (stream->r_obj, *(f->ptr_table.SL_IID_RECORD), &stream->r_rec);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error getting the audio recorder interface"));
        return PJ_ENOMEM;
    }

    // Get the recorder buffer queue interface
    result = (*stream->r_obj)->GetInterface (stream->r_obj,
                                             *(f->ptr_table.SL_IID_ANDROIDSIMPLEBUFFERQUEUE),
                                             &stream->r_buf_queue);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error getting the audio recorder buffer queue"));
        return PJ_ENOMEM;
    }

    // Register buffer queue callback
    result = (*stream->r_buf_queue)->RegisterCallback (stream->r_buf_queue, rec_callback, stream);
    if (result != SL_RESULT_SUCCESS) {
        PJ_LOG (2,(THIS_FILE, "Error registering the recorder queue callback"));
        return PJ_EUNKNOWN;
    }

    return PJ_SUCCESS;
}


static pj_status_t sles_factory_create_stream(pjmedia_aud_dev_factory *f,
                                              const pjmedia_aud_param *param,
                                              pjmedia_aud_rec_cb rec_cb,
                                              pjmedia_aud_play_cb play_cb,
                                              void *user_data,
                                              pjmedia_aud_stream **p_strm)
{
    struct sles_factory *sf = (struct sles_factory*)f;
    pj_status_t status;
    pj_pool_t* pool;
    struct sles_stream* stream;

    pool = pj_pool_create (sf->pf, "sles%p", 1024, 1024, NULL);
    if (!pool)
        return PJ_ENOMEM;

    stream = PJ_POOL_ZALLOC_T (pool, struct sles_stream);
    stream->base.op   = &sles_stream_op;
    stream->f         = sf;
    stream->pool      = pool;
    stream->user_data = user_data;
    stream->play_cb   = play_cb;
    stream->rec_cb    = rec_cb;
    pj_memcpy (&stream->param, param, sizeof(*param));

    // Allocate buffers
    status = allocate_buffers (stream);
    if (status != PJ_SUCCESS) {
        pj_pool_release (pool);
        return status;
    }

    // Init playback
    if (param->dir & PJMEDIA_DIR_PLAYBACK) {
        status = open_play (stream);
        if (status != PJ_SUCCESS) {
            destroy_sles_audio (stream);
            pj_pool_release (pool);
            return status;
        }
    }

    // Init capture
    if (param->dir & PJMEDIA_DIR_CAPTURE) {
        status = open_rec (stream);
        if (status != PJ_SUCCESS) {
            destroy_sles_audio (stream);
            pj_pool_release (pool);
            return status;
        }
    }

    *p_strm = &stream->base;
    return PJ_SUCCESS;
}


static pj_status_t sles_stream_get_param(pjmedia_aud_stream *s,
                                         pjmedia_aud_param *param)
{
    struct sles_stream *stream = (struct sles_stream*)s;

    PJ_ASSERT_RETURN(stream && param, PJ_EINVAL);

    pj_memcpy(param, &stream->param, sizeof(*param));
    return PJ_SUCCESS;
}


static pj_status_t sles_stream_get_cap(pjmedia_aud_stream *s,
                                       pjmedia_aud_dev_cap cap,
                                       void *value)
{
    pj_status_t status = PJ_SUCCESS;
    struct sles_stream *stream = (struct sles_stream*) s;

    PJ_ASSERT_RETURN(s && value, PJ_EINVAL);

    if (cap == PJMEDIA_AUD_DEV_CAP_INPUT_LATENCY && stream->param.dir & PJMEDIA_DIR_CAPTURE) {
        *(unsigned*)value = stream->param.input_latency_ms;
    }else if (cap == PJMEDIA_AUD_DEV_CAP_OUTPUT_LATENCY && stream->param.dir & PJMEDIA_DIR_PLAYBACK) {
        *(unsigned*)value = stream->param.output_latency_ms;
    }else if (cap == PJMEDIA_AUD_DEV_CAP_OUTPUT_ROUTE && stream->param.dir & PJMEDIA_DIR_PLAYBACK) {
        *(unsigned*)value = stream->param.output_route;
    }else if (cap == PJMEDIA_AUD_DEV_CAP_EC && stream->param.dir & PJMEDIA_DIR_CAPTURE && stream->f->device_has_hw_ec) {
        *(pj_bool_t*)value = stream->param.ec_enabled;
    }else{
        status = PJMEDIA_EAUD_INVCAP;
    }

    return status;
}


static pj_status_t sles_stream_set_cap(pjmedia_aud_stream *s,
                                       pjmedia_aud_dev_cap cap,
                                       const void *value)
{
    pj_status_t status = PJ_SUCCESS;
    struct sles_stream *stream = (struct sles_stream*) s;

    PJ_ASSERT_RETURN(s && value, PJ_EINVAL);

    if (cap == PJMEDIA_AUD_DEV_CAP_INPUT_LATENCY && stream->param.dir & PJMEDIA_DIR_CAPTURE) {
        stream->param.input_latency_ms = *(unsigned*)value;
    }else if (cap == PJMEDIA_AUD_DEV_CAP_OUTPUT_LATENCY && stream->param.dir & PJMEDIA_DIR_PLAYBACK) {
        stream->param.output_latency_ms = *(unsigned*)value;
    }else if (cap == PJMEDIA_AUD_DEV_CAP_OUTPUT_ROUTE && stream->param.dir & PJMEDIA_DIR_PLAYBACK) {
        stream->param.output_route = *(unsigned*)value;
    }else if (cap == PJMEDIA_AUD_DEV_CAP_EC && stream->param.dir & PJMEDIA_DIR_CAPTURE && stream->f->device_has_hw_ec) {
        stream->param.ec_enabled = *(pj_bool_t*)value;
    }else{
        status = PJMEDIA_EAUD_INVCAP;
    }

    return status;
}


static pj_status_t sles_stream_start(pjmedia_aud_stream *s)
{
    struct sles_stream *stream = (struct sles_stream*) s;
    SLresult result;
    pj_status_t status = PJ_SUCCESS;
    unsigned i;

    PJ_ASSERT_RETURN(s, PJ_EINVAL);

    if (stream->param.dir & PJMEDIA_DIR_PLAYBACK) {
        // Make sure the player is stopped
        result = (*stream->p_play)->SetPlayState (stream->p_play, SL_PLAYSTATE_STOPPED);
        if (result != SL_RESULT_SUCCESS)
            PJ_LOG (2,(THIS_FILE, "Error stopping the audio player"));

        // Flush buffer queue
        result = (*stream->p_buf_queue)->Clear (stream->p_buf_queue);
        if (result != SL_RESULT_SUCCESS) {
            PJ_LOG (2,(THIS_FILE, "Error flushing audio player buffer queue"));
            return PJ_EUNKNOWN;
        }

        // Initialize buffer queue
        stream->p_buf_index = 0;
        for (i=0; i<stream->p_num_buffers; i++) {
            pj_bzero (stream->p_buf[i], stream->p_buf_size);
            result = (*stream->p_buf_queue)->Enqueue (stream->p_buf_queue,
                                                      stream->p_buf[i],
                                                      stream->p_buf_size);
            if (result != SL_RESULT_SUCCESS) {
                PJ_LOG (2,(THIS_FILE, "Error adding buffer to play queue"));
                return PJ_EUNKNOWN;
            }
        }

        // Start playing
        result = (*stream->p_play)->SetPlayState (stream->p_play, SL_PLAYSTATE_PLAYING);
        if (result != SL_RESULT_SUCCESS) {
            PJ_LOG (2,(THIS_FILE, "Error starting audio player"));
            return PJ_EUNKNOWN;
        }
    }

    if (stream->param.dir & PJMEDIA_DIR_CAPTURE) {
        // Make sure the recorder is stopped
        result = (*stream->r_rec)->SetRecordState (stream->r_rec, SL_RECORDSTATE_STOPPED);
        if (result != SL_RESULT_SUCCESS)
            PJ_LOG (2,(THIS_FILE, "Error stopping the audio recorder"));

        // Flush buffer queue
        result = (*stream->r_buf_queue)->Clear (stream->r_buf_queue);
        if (result != SL_RESULT_SUCCESS) {
            PJ_LOG (2,(THIS_FILE, "Error flushing audio recorder buffer queue"));
            return PJ_EUNKNOWN;
        }

        // Initialize buffer queue
        stream->r_buf_index = 0;
        for (i=0; i<stream->r_num_buffers; i++) {
            pj_bzero (stream->r_buf[i], stream->r_buf_size);
            result = (*stream->r_buf_queue)->Enqueue (stream->r_buf_queue,
                                                      stream->r_buf[i],
                                                      stream->r_buf_size);
            if (result != SL_RESULT_SUCCESS) {
                PJ_LOG (2,(THIS_FILE, "Error adding buffer to recorder queue"));
                return PJ_EUNKNOWN;
            }
        }

        // Start recording
        result = (*stream->r_rec)->SetRecordState (stream->r_rec, SL_RECORDSTATE_RECORDING);
        if (result != SL_RESULT_SUCCESS) {
            PJ_LOG (2,(THIS_FILE, "Error starting audio recorder"));
            return PJ_EUNKNOWN;
        }
    }

    return status;
}


static pj_status_t sles_stream_stop(pjmedia_aud_stream *s)
{
    struct sles_stream *stream = (struct sles_stream*) s;
    SLresult result;
    pj_status_t status = PJ_SUCCESS;

    PJ_ASSERT_RETURN(s, PJ_EINVAL);

    if (stream->param.dir & PJMEDIA_DIR_PLAYBACK) {
        // Stop playing
        result = (*stream->p_play)->SetPlayState (stream->p_play, SL_PLAYSTATE_STOPPED);
        if (result != SL_RESULT_SUCCESS) {
            PJ_LOG (2,(THIS_FILE, "Error stopping the audio player"));
            status = PJ_EUNKNOWN;
        }

        // Flush buffer queue
        result = (*stream->p_buf_queue)->Clear (stream->p_buf_queue);
        if (result != SL_RESULT_SUCCESS) {
            PJ_LOG (2,(THIS_FILE, "Error flushing audio player buffer queue"));
            status = PJ_EUNKNOWN;
        }
    }

    if (stream->param.dir & PJMEDIA_DIR_CAPTURE) {
        // Stop recording
        result = (*stream->r_rec)->SetRecordState (stream->r_rec, SL_RECORDSTATE_STOPPED);
        if (result != SL_RESULT_SUCCESS) {
            PJ_LOG (2,(THIS_FILE, "Error stopping the audio recorder"));
            return PJ_EUNKNOWN;
        }

        // Flush buffer queue
        result = (*stream->r_buf_queue)->Clear (stream->r_buf_queue);
        if (result != SL_RESULT_SUCCESS) {
            PJ_LOG (2,(THIS_FILE, "Error flushing audio recorder buffer queue"));
            return PJ_EUNKNOWN;
        }
    }

    return status;
}


static pj_status_t sles_stream_destroy(pjmedia_aud_stream *s)
{
    struct sles_stream *stream = (struct sles_stream*) s;
    PJ_ASSERT_RETURN(s, PJ_EINVAL);

    destroy_sles_audio (stream);
    pj_pool_release (stream->pool);

    return PJ_SUCCESS;
}



#endif
