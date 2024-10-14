# include <stdlib.h>
# include <stdio.h>
# include <stdint.h>

typedef struct {
    uint16_t bits;
} bf16_t;


static inline bf16_t fp32_to_bf16(float s)
{
    bf16_t h;
    union {
        float f;
        uint32_t i;
    } u = {.f = s};
    if ((u.i & 0x7fffffff) > 0x7f800000) { /* NaN */
        h.bits = (u.i >> 16) | 64;         /* force to quiet */
        return h;                                                                                                                                             
    }
    h.bits = (u.i + (0x7fff + ((u.i >> 0x10) & 1))) >> 0x10;
    return h;
}


int short_clz(short x)
{
    x |= (x >> 1);
    x |= (x >> 2);
    x |= (x >> 4);
    x |= (x >> 8);
    
    x -= ((x >> 1) & 0x5555);
    x = ((x >> 2) & 0x3333) + (x & 0x3333);
    x = ((x >> 4) + x) & 0x0f0f;
    x += (x >> 8);

    return (16 - (x & 0x7f));
}

short bf16_sum(short a, short b){
    unsigned short rst_sign, rst_exp, rst_mant, rst;// RESULT, rst = rst_sign | rst_exp | rst_mant;

    unsigned short a_sign = a >> 15;
    unsigned short a_exp = (unsigned short)(a << 1) >> 8;
    unsigned short a_mant = (a & 127) | 128;// mantissa

    unsigned short b_sign = b >> 15;
    unsigned short b_exp = (unsigned short)(b << 1) >> 8;
    unsigned short b_mant = (b & 127) | 128;// mantissa

    if(a_exp > b_exp){
        unsigned short sha = a_exp - b_exp;//shift amount
        b_mant >>= sha;
        if(a_sign ^ b_sign)
            rst_mant = a_mant - b_mant;
        else
            rst_mant = a_mant + b_mant;
        rst_exp = a_exp;
        rst_sign = a_sign;
    }
    else{
        unsigned short sha = b_exp - a_exp;//shift amount
        a_mant >>= sha;
        if(a_sign ^ b_sign)
            rst_mant = b_mant - a_mant;
        else
            rst_mant = a_mant + b_mant;
        rst_exp = b_exp;
        rst_sign = b_sign;
    }

    //normalize
    int num_lz = short_clz(rst_mant);
    if(num_lz <= 8){
        num_lz = 8 - num_lz;
        rst_mant >>= num_lz;
        rst_exp += num_lz; 
    }
    else{
        num_lz -= 8;
        rst_mant <<= num_lz;
        rst_exp -= num_lz;
    }
      
    rst_sign <<= 15;
    rst_exp <<= 7;
    rst_mant -= 128;
    rst = rst_sign | rst_exp | rst_mant;

    return rst;
}



int main(){

    // fp32 input data
    float fp32_arr[] = {9.8125, -100.0, 58.75}; //0x411d0000, 0xc2c80000, 0x426b0000
    int fp32_arr_len = 3;
    
    printf("input data:\n");
    for(int i=0; i<fp32_arr_len; i++){
        printf("%f ", fp32_arr[i]);
    }
    printf("\n");

    // convert array to bf16
    int bf16_arr_len = 3;
    bf16_t bf16_arr[bf16_arr_len];
    for(int i=0; i<bf16_arr_len; i++){
        bf16_arr[i] = fp32_to_bf16(fp32_arr[i]);
    }

    printf("input data (bf16 format):\n");
    for(int i=0; i<bf16_arr_len; i++){
        printf("0x%x ", bf16_arr[i].bits);
    }
    printf("\n");

    // do bf16 running sum
    for(int i=1; i < bf16_arr_len; i++){
        bf16_arr[i].bits = bf16_sum(bf16_arr[i].bits, bf16_arr[i-1].bits);
    }

    printf("running sum array result (bf16 format):\n");
    for(int i=0; i<bf16_arr_len; i++){
        printf("0x%x ", bf16_arr[i].bits);
    }
    printf("\n");

  

    return 0;
}