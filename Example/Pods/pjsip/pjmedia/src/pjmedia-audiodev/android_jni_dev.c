/**
 * Copyright (C) 2011 Twilio, Inc.
 * All rights reserved.
 *
 * Brian Tarricone, 2011/11/08
 */

#if defined(PJMEDIA_AUDIO_DEV_HAS_ANDROID_JNI)

#include <pjmedia_audiodev.h>
#include <pj/assert.h>
#include <pj/log.h>
#include <pj/os.h>
#include <pj/pool.h>
#include <pjmedia/errno.h>

#include <jni.h>

#define THIS_FILE "android_jni_dev.c"

// copied from http://developer.android.com/reference/android/media/AudioFormat.html
// maybe should look these up at runtime...
#define AF_CHANNEL_OUT_MONO          4
#define AF_CHANNEL_OUT_STEREO       12
#define AF_CHANNEL_IN_MONO          16
#define AF_CHANNEL_IN_STEREO        12
#define AF_ENCODING_PCM_8BIT         3
#define AF_ENCODING_PCM_16BIT        2
// and from http://developer.android.com/reference/android/media/AudioTrack.html
#define AT_MODE_STREAM               1
#define AT_ERROR                    -1
#define AT_ERROR_BAD_VALUE          -2
#define AT_ERROR_INVALID_OPERATION  -3
// and from http://developer.android.com/reference/android/media/AudioRecord.html
#define AR_ERROR                    -1
#define AR_ERROR_BAD_VALUE          -2
#define AR_ERROR_INVALID_OPERATION  -3
// and from http://developer.android.com/reference/android/media/AudioManager.html
#define AM_STREAM_VOICE_CALL         0
// and from http://developer.android.com/reference/android/media/MediaRecorder.AudioSource.html
#define MRAS_MIC                     1
#define MRAS_VOICE_COMMUNICATION     7

enum class_type
{
    CLASS_AUDIO_TRACK = 0,
    CLASS_AUDIO_RECORD,
    N_CLASSES
};

static const char *class_names[] =
{
    "android/media/AudioTrack",
    "android/media/AudioRecord",
};

// AT = AudioTrack, AR = AudioRecord
enum
{
    METHOD_AT_CONSTRUCT = 0,
    METHOD_AT_FLUSH,
    METHOD_AT_GET_MIN_BUFFER_SIZE,
    METHOD_AT_PLAY,
    METHOD_AT_RELEASE,
    METHOD_AT_STOP,
    METHOD_AT_WRITE,

    METHOD_AR_CONSTRUCT,
    METHOD_AR_GET_MIN_BUFFER_SIZE,
    METHOD_AR_READ,
    METHOD_AR_RELEASE,
    METHOD_AR_START_RECORDING,
    METHOD_AR_STOP,

    N_METHODS
};

static const struct
{
    const enum class_type class_type;
    const char *method_name;
    const char *signature;
    const int is_static;
} method_info[] = 
{
    { CLASS_AUDIO_TRACK, "<init>", "(IIIIII)V", 0 },
    { CLASS_AUDIO_TRACK, "flush", "()V", 0 },
    { CLASS_AUDIO_TRACK, "getMinBufferSize", "(III)I", 1 },
    { CLASS_AUDIO_TRACK, "play", "()V", 0 },
    { CLASS_AUDIO_TRACK, "release", "()V", 0 },
    { CLASS_AUDIO_TRACK, "stop", "()V", 0 },
    { CLASS_AUDIO_TRACK, "write", "([BII)I", 0},

    { CLASS_AUDIO_RECORD, "<init>", "(IIIII)V", 0 },
    { CLASS_AUDIO_RECORD, "getMinBufferSize", "(III)I", 1 },
    { CLASS_AUDIO_RECORD, "read", "(Ljava/nio/ByteBuffer;I)I", 0 },
    { CLASS_AUDIO_RECORD, "release", "()V", 0 },
    { CLASS_AUDIO_RECORD, "startRecording", "()V", 0 },
    { CLASS_AUDIO_RECORD, "stop", "()V", 0 },
};


typedef struct jni_factory
{
    pjmedia_aud_dev_factory  base;
    pj_pool_factory         *pf;
    pj_pool_t               *pool;
    pjmedia_aud_dev_info     dev_info;

    JavaVM *jvm;

    jclass classes[N_CLASSES];
    jmethodID methods[N_METHODS];
} jni_factory;

typedef struct jni_stream
{
    pjmedia_aud_stream base;
    struct jni_factory *jf;

    pj_pool_t *pool;
    void *user_data;
    pjmedia_aud_param param;
    int running;

    pjmedia_aud_play_cb rec_cb;
    pj_thread_t *r_thread;

    pjmedia_aud_play_cb play_cb;
    pj_thread_t *p_thread;
} jni_stream;


static inline JNIEnv *
jni_get_env(JavaVM *jvm,
            int *needed_to_attach)
{
    JNIEnv *env = NULL;
    *needed_to_attach = 0;

    (*jvm)->GetEnv(jvm, (void **)&env, JNI_VERSION_1_4);
    if (!env) {
        (*jvm)->AttachCurrentThread(jvm, &env, NULL);
        *needed_to_attach = 1;
    }

    return env;
}

static inline void
jni_release_env(JavaVM *jvm)
{
    (*jvm)->DetachCurrentThread(jvm);
}


static pj_status_t
jni_cache_stuff(jni_factory *jf)
{
    pj_status_t ret = PJ_SUCCESS;
    JNIEnv *env = NULL;
    int jvm_needs_detach = 0;
    int i;

    if (!jf->jvm)
        return PJ_EINVAL;

    if (!(env = jni_get_env(jf->jvm, &jvm_needs_detach)))
        return PJ_EUNKNOWN;

    // cache classes
    for (i = 0; i < N_CLASSES; ++i) {
        jclass cls = (*env)->FindClass(env, class_names[i]);
        if (!cls) {
            ret = PJ_ENOTFOUND;
            goto out;
        }

        jf->classes[i] = (*env)->NewGlobalRef(env, cls);
        if (!jf->classes[i]) {
            ret = PJ_ENOMEM;
            goto out;
        }
    }

    // cache method IDs
    for (i = 0; i < N_METHODS; ++i) {
        jclass cls = jf->classes[method_info[i].class_type];
        jmethodID meth = NULL;

        if (method_info[i].is_static)
            meth = (*env)->GetStaticMethodID(env, cls, method_info[i].method_name, method_info[i].signature);
        else
            meth = (*env)->GetMethodID(env, cls, method_info[i].method_name, method_info[i].signature);
        if (!meth) {
            ret = PJ_ENOTFOUND;
            goto out;
        }

        jf->methods[i] = meth;
    }

out:
    if (jvm_needs_detach)
        jni_release_env(jf->jvm);

    return ret;
}

static pj_status_t
jni_drop_caches(jni_factory *jf)
{
    JNIEnv *env = NULL;
    int jvm_needs_detach = 0;
    int i;

    if (!jf->jvm)
        return PJ_EINVAL;

    if (!(env = jni_get_env(jf->jvm, &jvm_needs_detach)))
        return PJ_EUNKNOWN;

    for (i = 0; i < N_CLASSES; ++i) {
        if (jf->classes[i])
            (*env)->DeleteGlobalRef(env, jf->classes[i]);
    }

    if (jvm_needs_detach)
        jni_release_env(jf->jvm);

    return PJ_SUCCESS;
}


static int
jni_rec_thread(void *arg)
{
    pj_status_t ret = PJ_SUCCESS;
    jni_stream *stream = (jni_stream *)arg;
    jni_factory *jf = stream->jf;
    pjmedia_aud_param *param = &stream->param;
    pj_thread_desc thread_desc;
    JNIEnv *env = NULL;
    int jvm_needs_detach = 0;

    jint buffer_size;
    const int rec_size = param->samples_per_frame * (param->bits_per_sample / 8);
    const int frames_per_read = param->samples_per_frame / param->channel_count;
    jint channel_config;
    jint audio_format;

    jobject audio_record = NULL;
    jbyte *buf = NULL;
    jobject byte_buffer = NULL;
    pj_timestamp timestamp;

    if (!pj_thread_is_registered())
        pj_thread_register("jni_rec_thread", thread_desc, &stream->r_thread);

    if (!(env = jni_get_env(jf->jvm, &jvm_needs_detach)))
        return PJ_EUNKNOWN;
    
    switch (param->channel_count) {
        case 1:
            channel_config = AF_CHANNEL_IN_MONO;
            break;
        case 2:
            channel_config = AF_CHANNEL_IN_STEREO;
            break;
        default:
            ret = PJ_EINVAL;
            goto out;
    }

    switch (param->bits_per_sample) {
        case 8:
            audio_format = AF_ENCODING_PCM_8BIT;
            break;
        case 16:
            audio_format = AF_ENCODING_PCM_16BIT;
            break;
        default:
            ret = PJ_EINVAL;
            goto out;
    }

    buffer_size = (*env)->CallStaticIntMethod(env, jf->classes[CLASS_AUDIO_RECORD],
                                              jf->methods[METHOD_AR_GET_MIN_BUFFER_SIZE],
                                              param->clock_rate, channel_config, audio_format);
    if (buffer_size == AR_ERROR) {
        ret = PJ_EUNKNOWN;
        goto out;
    } else if (buffer_size == AR_ERROR_BAD_VALUE) {
        ret = PJ_EINVAL;
        goto out;
    }

    // magic constants.  not sure why.
    if (buffer_size <= 4096)
        buffer_size = 4096 * 3/2;
    if (buffer_size % 2)
        ++buffer_size;

    audio_record = (*env)->NewObject(env, jf->classes[CLASS_AUDIO_RECORD], jf->methods[METHOD_AR_CONSTRUCT],
                                     MRAS_MIC, param->clock_rate, channel_config,
                                     audio_format, buffer_size);
    if (!audio_record) {
        ret = PJ_EUNKNOWN;
        goto out;
    }

    (*env)->CallVoidMethod(env, audio_record, jf->methods[METHOD_AR_START_RECORDING]);
    if ((*env)->ExceptionOccurred(env)) {
        ret = PJ_EUNKNOWN;
        goto out;
    }

    buf = (jbyte *)pj_pool_alloc(stream->pool, rec_size);
    if (!buf) {
        ret = PJ_ENOMEM;
        goto out;
    }

    byte_buffer = (*env)->NewDirectByteBuffer(env, (void *)buf, rec_size);
    if (!byte_buffer) {
        ret = PJ_ENOMEM;
        goto out;
    }

    timestamp.u64 = 0;
    while (stream->running) {
        pj_status_t status;
        pjmedia_frame frame;
        jint read;

        read = (*env)->CallIntMethod(env, audio_record, jf->methods[METHOD_AR_READ],
                                     byte_buffer, rec_size);
        if (read == AR_ERROR_INVALID_OPERATION) {
            ret = PJ_EINVALIDOP;
            break;
        } else if (read == AR_ERROR_BAD_VALUE) {
            ret = PJ_EINVAL;
            break;
        }

        frame.type = PJMEDIA_FRAME_TYPE_AUDIO;
        frame.buf = (void *)buf;
        frame.size = read;
        frame.timestamp.u64 = timestamp.u64;
        frame.bit_info = 0;

        status = stream->rec_cb(stream->user_data, &frame);
        if (status != PJ_SUCCESS)
            break;

        // FIXME: assuming read == frame.size == rec_size
        timestamp.u64 += frames_per_read;
    }

out:

    if (audio_record)
        (*env)->CallVoidMethod(env, audio_record, jf->methods[METHOD_AR_RELEASE]);

    if (jvm_needs_detach)
        jni_release_env(jf->jvm);

    return ret;
}

static int
jni_play_thread(void *arg)
{
    pj_status_t ret = PJ_SUCCESS;
    jni_stream *stream = (jni_stream *)arg;
    jni_factory *jf = stream->jf;
    pjmedia_aud_param *param = &stream->param;
    pj_thread_desc thread_desc;
    JNIEnv *env = NULL;
    int jvm_needs_detach = 0;

    jint buffer_size;
    const int play_size = param->samples_per_frame * (param->bits_per_sample / 8);
    const int frames_per_write = param->samples_per_frame / param->channel_count;
    jint channel_config;
    jint audio_format;

    jobject audio_track = NULL;
    jbyteArray buf_obj = NULL;
    jboolean is_copy = JNI_FALSE;
    jbyte *buf = NULL;
    pj_timestamp timestamp;

    if (!pj_thread_is_registered())
        pj_thread_register("jni_play_thread", thread_desc, &stream->p_thread);

    if (!(env = jni_get_env(jf->jvm, &jvm_needs_detach)))
        return PJ_EUNKNOWN;

    switch (param->channel_count) {
        case 1:
            channel_config = AF_CHANNEL_OUT_MONO;
            break;
        case 2:
            channel_config = AF_CHANNEL_OUT_STEREO;
            break;
        default:
            ret = PJ_EINVAL;
            goto out;
    }

    switch (param->bits_per_sample) {
        case 8:
            audio_format = AF_ENCODING_PCM_8BIT;
            break;
        case 16:
            audio_format = AF_ENCODING_PCM_16BIT;
            break;
        default:
            ret = PJ_EINVAL;
            goto out;
    }

    buffer_size = (*env)->CallStaticIntMethod(env, jf->classes[CLASS_AUDIO_TRACK],
                                              jf->methods[METHOD_AT_GET_MIN_BUFFER_SIZE],
                                              param->clock_rate, channel_config, audio_format);
    if (buffer_size == AT_ERROR) {
        ret = PJ_EUNKNOWN;
        goto out;
    } else if (buffer_size == AT_ERROR_BAD_VALUE) {
        ret = PJ_EINVAL;
        goto out;
    }

    // more magic numbers... not srue where they come from.
    if (buffer_size <= 2*2*1024*param->clock_rate/8000)
        buffer_size = 2*2*1024*param->clock_rate/8000;
    if (buffer_size % 2)
        ++buffer_size;

    audio_track = (*env)->NewObject(env, jf->classes[CLASS_AUDIO_TRACK], jf->methods[METHOD_AT_CONSTRUCT],
                                    AM_STREAM_VOICE_CALL, param->clock_rate, channel_config,
                                    audio_format, buffer_size, AT_MODE_STREAM);
    if (!audio_track) {
        ret = PJ_EUNKNOWN;
        goto out;
    }

    (*env)->CallVoidMethod(env, audio_track, jf->methods[METHOD_AT_PLAY]);
    if ((*env)->ExceptionOccurred(env)) {
        (*env)->ExceptionDescribe(env);
        ret = PJ_EUNKNOWN;
        goto out;
    }

    buf_obj = (*env)->NewByteArray(env, play_size);
    if (!buf_obj) {
        ret = PJ_ENOMEM;
        goto out;
    }

    buf = (*env)->GetByteArrayElements(env, buf_obj, &is_copy);
    if (!buf) {
        ret = PJ_ENOMEM;  // ?
        goto out;
    }

    timestamp.u64 = 0;
    while (stream->running) {
        pj_status_t status;
        pjmedia_frame frame;
        jint written;

        pj_bzero(buf, play_size);
        frame.type = PJMEDIA_FRAME_TYPE_AUDIO;
        frame.buf = (void *)buf;
        frame.size = play_size;
        frame.timestamp.u64 = timestamp.u64;
        frame.bit_info = 0;

        status = stream->play_cb(stream->user_data, &frame);
        if (status != PJ_SUCCESS)
            break;

        if (frame.type != PJMEDIA_FRAME_TYPE_AUDIO)
            continue;

        if (is_copy) {
            // suck.  this'll slow us down a little
            // my understanding is that JNI_COMMIT copies the data
            // back but does not release the array.  need to make
            // sure the last bit is actually true.
            (*env)->ReleaseByteArrayElements(env, buf_obj, buf, JNI_COMMIT);
        }

        written = (*env)->CallIntMethod(env, audio_track, jf->methods[METHOD_AT_WRITE],
                                        buf_obj, 0, frame.size);
        if (written == AT_ERROR_INVALID_OPERATION) {
            ret = PJ_EINVALIDOP;
            break;
        } else if (written == AT_ERROR_BAD_VALUE) {
            ret = PJ_EINVAL;
            break;
        }

        // FIXME: assuming written == frame.size == play_size
        timestamp.u64 += frames_per_write;
    }

out:

    if (buf_obj && buf)
        (*env)->ReleaseByteArrayElements(env, buf_obj, buf, 0);

    if (audio_track)
        (*env)->CallVoidMethod(env, audio_track, jf->methods[METHOD_AT_RELEASE]);

    if (jvm_needs_detach)
        jni_release_env(jf->jvm);

    return ret;
}

static pj_status_t
jni_factory_init(pjmedia_aud_dev_factory *f)
{
    pj_status_t status;
    jni_factory *jf = (jni_factory *)f;
    PJ_ASSERT_RETURN(jf != NULL, PJ_EINVAL);

    pj_bzero(&jf->dev_info, sizeof(jf->dev_info));
    strcpy(jf->dev_info.driver, "Android JNI Bridge");
    strcpy(jf->dev_info.name, "JNI");
    jf->dev_info.output_count = 1;
    jf->dev_info.input_count  = 1;
    jf->dev_info.default_samples_per_sec = 16000;

    status = jni_cache_stuff(jf);
    if (status != PJ_SUCCESS)
        return status;

    return PJ_SUCCESS;
}

static pj_status_t
jni_factory_destroy(pjmedia_aud_dev_factory *f)
{
    jni_factory *jf = (jni_factory *)f;
    jni_drop_caches(jf);
    return PJ_SUCCESS;
}

static unsigned
jni_factory_get_dev_count(pjmedia_aud_dev_factory *f)
{
    return 1;
}

static pj_status_t
jni_factory_get_dev_info(pjmedia_aud_dev_factory *f,
                         unsigned index,
                         pjmedia_aud_dev_info *info)
{
    jni_factory *jf = (jni_factory *)f;

    PJ_ASSERT_RETURN(index == 0 && jf, PJ_EINVAL);

    pj_memcpy(info, &jf->dev_info, sizeof(*info));
    info->caps = PJMEDIA_AUD_DEV_CAP_INPUT_LATENCY |
                 PJMEDIA_AUD_DEV_CAP_OUTPUT_LATENCY |
                 PJMEDIA_AUD_DEV_CAP_OUTPUT_ROUTE;

    return PJ_SUCCESS;
}

static pj_status_t
jni_factory_default_param(pjmedia_aud_dev_factory *f,
                          unsigned index,
                          pjmedia_aud_param *param)
{
    jni_factory *jf = (jni_factory *)f;

    PJ_ASSERT_RETURN(index == 0 && jf, PJ_EINVAL);

    pj_bzero(param, sizeof(*param));
    param->dir = PJMEDIA_DIR_CAPTURE_PLAYBACK;
    param->rec_id = 0;
    param->play_id = 0;
    param->clock_rate = jf->dev_info.default_samples_per_sec;
    param->channel_count = 1;
    param->samples_per_frame = param->clock_rate * 20 / 1000;
    param->bits_per_sample = 16;
    param->flags = jf->dev_info.caps;
    param->input_latency_ms = PJMEDIA_SND_DEFAULT_REC_LATENCY;
    param->output_latency_ms = PJMEDIA_SND_DEFAULT_PLAY_LATENCY;

    return PJ_SUCCESS;
}

// see below for jni_factory_create_stream()


static pj_status_t
jni_stream_get_param(pjmedia_aud_stream *s,
                     pjmedia_aud_param *param)
{
    jni_stream *stream = (jni_stream*)s;
    PJ_ASSERT_RETURN(stream && param, PJ_EINVAL);
    pj_memcpy(param, &stream->param, sizeof(*param));
    return PJ_SUCCESS;
}

static pj_status_t
jni_stream_get_cap(pjmedia_aud_stream *s,
                   pjmedia_aud_dev_cap cap,
                   void *value)
{
    pj_status_t status = PJ_SUCCESS;
    jni_stream *stream = (jni_stream *)s;

    PJ_ASSERT_RETURN(s && value, PJ_EINVAL);

    if (cap == PJMEDIA_AUD_DEV_CAP_INPUT_LATENCY && stream->param.dir & PJMEDIA_DIR_CAPTURE)
        *(unsigned*)value = stream->param.input_latency_ms;
    else if (cap == PJMEDIA_AUD_DEV_CAP_OUTPUT_LATENCY && stream->param.dir & PJMEDIA_DIR_PLAYBACK)
        *(unsigned*)value = stream->param.output_latency_ms;
    else if (cap == PJMEDIA_AUD_DEV_CAP_OUTPUT_ROUTE && stream->param.dir & PJMEDIA_DIR_PLAYBACK)
        *(unsigned*)value = stream->param.output_route;
    else
        status = PJMEDIA_EAUD_INVCAP;

    return status;
}

static pj_status_t
jni_stream_set_cap(pjmedia_aud_stream *s,
                   pjmedia_aud_dev_cap cap,
                   const void *value)
{
    pj_status_t status = PJ_SUCCESS;
    jni_stream *stream = (jni_stream *)s;

    PJ_ASSERT_RETURN(s && value, PJ_EINVAL);

    if (cap == PJMEDIA_AUD_DEV_CAP_INPUT_LATENCY && stream->param.dir & PJMEDIA_DIR_CAPTURE)
        stream->param.input_latency_ms = *(unsigned*)value;
    else if (cap == PJMEDIA_AUD_DEV_CAP_OUTPUT_LATENCY && stream->param.dir & PJMEDIA_DIR_PLAYBACK)
        stream->param.output_latency_ms = *(unsigned*)value;
    else if (cap == PJMEDIA_AUD_DEV_CAP_OUTPUT_ROUTE && stream->param.dir & PJMEDIA_DIR_PLAYBACK)
        stream->param.output_route = *(unsigned*)value;
    else
        status = PJMEDIA_EAUD_INVCAP;

    return status;
}

static pj_status_t
jni_stream_stop(pjmedia_aud_stream *s)
{
    jni_stream *stream = (jni_stream *)s;

    stream->running = 0;

    if (stream->p_thread) {
        pj_thread_join(stream->p_thread);
        stream->p_thread = NULL;
    }

    if (stream->r_thread) {
        pj_thread_join(stream->r_thread);
        stream->r_thread = NULL;
    }

    return PJ_SUCCESS;
}

static pj_status_t
jni_stream_start(pjmedia_aud_stream *s)
{
    jni_stream *stream = (jni_stream *)s;
    pjmedia_aud_param *param = &stream->param;
    pj_status_t status = PJ_SUCCESS;

    stream->running = 1;

    if (param->dir & PJMEDIA_DIR_PLAYBACK) {
        // start playback thread
        status = pj_thread_create(stream->pool, "jni_play", jni_play_thread, stream,
                                  PJ_THREAD_DEFAULT_STACK_SIZE, 0, &stream->p_thread);
        if (status != PJ_SUCCESS)
            goto out;
    }

    if (param->dir & PJMEDIA_DIR_CAPTURE) {
        // start record thread
        status = pj_thread_create(stream->pool, "jni_rec", jni_rec_thread, stream,
                                  PJ_THREAD_DEFAULT_STACK_SIZE, 0, &stream->r_thread);
        if (status != PJ_SUCCESS)
            goto out;
    }

out:

    if (status != PJ_SUCCESS)
        jni_stream_stop(s);

    return status;
}

static pj_status_t
jni_stream_destroy(pjmedia_aud_stream *s)
{
    jni_stream *stream = (jni_stream *)s;

    // FIXME: can this ever happen?
    if (stream->running)
        jni_stream_stop(s);

    if (stream->pool)
        pj_pool_release(stream->pool);

    return PJ_SUCCESS;
}


// need to put this guy lower since it uses jni_stream_op
static pj_status_t jni_factory_create_stream(pjmedia_aud_dev_factory *f,
                                             const pjmedia_aud_param *param,
                                             pjmedia_aud_rec_cb rec_cb,
                                             pjmedia_aud_play_cb play_cb,
                                             void *user_data,
                                             pjmedia_aud_stream **p_strm);

static pjmedia_aud_dev_factory_op jni_factory_op =
{
    &jni_factory_init,
    &jni_factory_destroy,
    &jni_factory_get_dev_count,
    &jni_factory_get_dev_info,
    &jni_factory_default_param,
    &jni_factory_create_stream
};

static pjmedia_aud_stream_op jni_stream_op =
{
    &jni_stream_get_param,
    &jni_stream_get_cap,
    &jni_stream_set_cap,
    &jni_stream_start,
    &jni_stream_stop,
    &jni_stream_destroy
};

static pj_status_t
jni_factory_create_stream(pjmedia_aud_dev_factory *f,
                          const pjmedia_aud_param *param,
                          pjmedia_aud_rec_cb rec_cb,
                          pjmedia_aud_play_cb play_cb,
                          void *user_data,
                          pjmedia_aud_stream **p_strm)
{
    jni_factory *jf = (jni_factory *)f;
    pj_pool_t *pool;
    jni_stream *stream;

    pool = pj_pool_create(jf->pf, "jni%p", 1024, 1024, NULL);
    if (!pool)
        return PJ_ENOMEM;

    stream = PJ_POOL_ZALLOC_T(pool, jni_stream);
    stream->base.op = &jni_stream_op;
    stream->jf = jf;
    stream->pool = pool;
    stream->user_data = user_data;
    stream->play_cb = play_cb;
    stream->rec_cb = rec_cb;
    pj_memcpy(&stream->param, param, sizeof(*param));

    *p_strm = &stream->base;

    return PJ_SUCCESS;
}


pjmedia_aud_dev_factory *
pjmedia_android_jni_factory(pj_pool_factory *pf,
                            JavaVM *jvm)
{
    struct jni_factory *jf;
    pj_pool_t *pool;

    pool = pj_pool_create(pf, "jni_aud", 256, 256, NULL);
    jf = PJ_POOL_ZALLOC_T(pool, jni_factory);
    jf->pf = pf;
    jf->pool = pool;
    jf->base.op = &jni_factory_op;
    jf->jvm = jvm;

    return &jf->base;
}

#endif  /* PJMEDIA_AUDIO_DEV_HAS_ANDROID_JNI */
