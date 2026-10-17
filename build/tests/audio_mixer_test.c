/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <assert.h>
#include <math.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef uint32_t UINT32, UInt32;
typedef unsigned char BYTE;
struct ios_stream {
    int started, mixable, is_float, sample_bits;
    UINT32 buffer_frames, channels, frame_bytes, sample_rate;
    BYTE *ring;
    uint64_t resample_phase;
    UINT32 refill_wait_frames;
    int refilling;
    _Atomic uint64_t underrun_callbacks, refill_callbacks, missing_device_frames, play_pos, write_pos;
};
#include "actual_mixer.h"

static struct ios_stream stream(UINT32 rate, UINT32 frames) {
    struct ios_stream s = {.started=1,.mixable=1,.is_float=1,.sample_bits=32,
        .buffer_frames=frames,.channels=2,.frame_bytes=8,.sample_rate=rate};
    s.ring=calloc(frames,8);assert(s.ring);
    float *p=(float *)s.ring;
    for (UINT32 i=0;i<frames;i++) { p[2*i]=(float)i/frames; p[2*i+1]=-p[2*i]; }
    atomic_store(&s.write_pos,frames);
    return s;
}
static void steady(void) {
    struct ios_stream s=stream(48000,48000);
    float out[960];
    for (int block=0;block<100;block++) {
        memset(out,0,sizeof(out));ios_mix_stream(&s,out,480,2,48000);
        for(int i=0;i<480;i++) {
            assert(out[2*i]==((float *)s.ring)[2*(block*480+i)]);
            assert(out[2*i+1]==-out[2*i]);
        }
    }
    assert(atomic_load(&s.play_pos)==48000);
    assert(!atomic_load(&s.underrun_callbacks));free(s.ring);
}
static void fractional(UINT32 rate, UINT32 device) {
    struct ios_stream a=stream(rate,rate*2),b=stream(rate,rate*2);
    float *one=calloc(device*2,sizeof(float)),*many=calloc(device*2,sizeof(float));assert(one&&many);
    ios_mix_stream(&a,one,device,2,device);
    UINT32 offset=0;
    while(offset<device) {
        UINT32 n=offset%991+127;if(n>device-offset)n=device-offset;
        ios_mix_stream(&b,many+offset*2,n,2,device);offset+=n;
    }
    assert(atomic_load(&a.play_pos)==rate && atomic_load(&b.play_pos)==rate);
    assert(a.resample_phase==0 && b.resample_phase==0);
    assert(!memcmp(one,many,device*2*sizeof(float)));
    free(one);free(many);free(a.ring);free(b.ring);
}
static void recovery(void) {
    struct ios_stream s=stream(48000,4800);
    float out[960];atomic_store(&s.write_pos,100);
    memset(out,0,sizeof(out));ios_mix_stream(&s,out,480,2,48000);
    assert(atomic_load(&s.play_pos)==100 && s.refilling);
    assert(atomic_load(&s.missing_device_frames)==380);
    atomic_store(&s.write_pos,200); /* a short final clip, below refill target */
    for(int i=0;i<4;i++) { memset(out,0,sizeof(out));ios_mix_stream(&s,out,480,2,48000);assert(atomic_load(&s.play_pos)==100); }
    memset(out,0,sizeof(out));ios_mix_stream(&s,out,480,2,48000);
    assert(atomic_load(&s.play_pos)==200); /* bounded; no lost short tail */
    atomic_store(&s.write_pos,2600);memset(out,0,sizeof(out));ios_mix_stream(&s,out,480,2,48000);
    assert(atomic_load(&s.play_pos)==680); /* enough queued: no extra delay */
    s.started=0;ios_mix_stream(&s,out,480,2,48000);assert(atomic_load(&s.play_pos)==680);
    free(s.ring);
}
static void formats_and_wrap(void) {
    struct ios_stream s=stream(48000,32);float out[32];
    atomic_store(&s.play_pos,28);atomic_store(&s.write_pos,44);
    memset(out,0,sizeof(out));ios_mix_stream(&s,out,16,2,48000);
    for(int i=0;i<16;i++) assert(out[i*2]==((float *)s.ring)[((28+i)%32)*2]);
    assert(atomic_load(&s.play_pos)==44);
    s.is_float=0;s.sample_bits=16;s.channels=1;s.frame_bytes=2;
    atomic_store(&s.play_pos,0);atomic_store(&s.write_pos,2);
    ((int16_t *)s.ring)[0]=16384;((int16_t *)s.ring)[1]=-32768;
    memset(out,0,sizeof(out));ios_mix_stream(&s,out,2,2,48000);
    assert(out[0]==0.5f&&out[1]==0.5f&&out[2]==-1&&out[3]==-1);
    s.sample_bits=32;s.frame_bytes=4;atomic_store(&s.play_pos,0);atomic_store(&s.write_pos,2);
    ((int32_t *)s.ring)[0]=1073741824;((int32_t *)s.ring)[1]=-2147483647-1;
    memset(out,0,sizeof(out));ios_mix_stream(&s,out,2,2,48000);
    assert(out[0]==0.5f&&out[2]==-1);free(s.ring);
}
int main(int argc, char **argv) {
    if(argc>1 && !strcmp(argv[1],"phase")) { fractional(44100,48000); return 0; }
    steady();recovery();formats_and_wrap();
    fractional(44100,48000);fractional(48000,44100);fractional(32000,48000);fractional(96000,48000);
    puts("iOS audio mixer: steady PCM, 4 rate pairs/partition invariance, wrap, mono/int formats, bounded refill and short-tail recovery passed");
}
