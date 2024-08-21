// concise visual debugging utils for glsl shader
// GL = Y starts at the bottom
// DX = Y starts at the top
#ifndef Y_STARTS_AT_BOTTOM
#define Y_STARTS_AT_BOTTOM 1
#endif


// Encoding logic

#define GPU_NUMBER_ENCODING_E        10u
#define GPU_NUMBER_ENCODING_DOT      11u
#define GPU_NUMBER_ENCODING_PLUS     12u
#define GPU_NUMBER_ENCODING_NEG      13u
#define GPU_NUMBER_ENCODING_INVALID  14u
#define GPU_NUMBER_ENCODING_EMPTY    15u

#define INV_LN_10 0.434294481903251827651128918916605082294397005803666566

#define pow10(x)            pow(10., float(x))
#define floorLog10(x)       floor(log(x) * INV_LN_10)


float fractInputReturnFloor(inout float x)
{
    float floored = floor(x);
    x -= floored;
    return floored;
}

struct RepBuffer
{
    uint    data;
    uint    index;
};


RepBuffer RepBuffer_init()
{
    RepBuffer repBuffer;
    repBuffer.data = 0u;
    repBuffer.index = 0u;
    return repBuffer;
}

void RepBuffer_push(inout RepBuffer repBuffer, uint value)
{
    repBuffer.data |= ((~value) & 15u) << (4u * repBuffer.index++);
}

void RepBuffer_pop(inout RepBuffer repBuffer, uint count)
{
    if(count > repBuffer.index) { count = repBuffer.index; }
    uint mask = ~0u;
    mask >>= ((count - repBuffer.index) * 4u);
    repBuffer.data &= mask;
    repBuffer.index -= count;
}


uint RepBuffer_remainingSpace(RepBuffer repBuffer)
{
    return 8u - repBuffer.index;
}


uint RepBuffer_get(RepBuffer repBuffer)
{
    return ~repBuffer.data;
}


uint RepBuffer_getZero()
{
    RepBuffer repBuffer = RepBuffer_init();
    RepBuffer_push(repBuffer, 0u);
    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_DOT);
    RepBuffer_push(repBuffer, 0u);
    return RepBuffer_get(repBuffer);
}

uint RepBuffer_getNan()
{
    RepBuffer repBuffer = RepBuffer_init();
    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_INVALID);
    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_DOT);
    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_INVALID);
    return RepBuffer_get(repBuffer);
}

uint RepBuffer_getPosInf()
{
    RepBuffer repBuffer = RepBuffer_init();
    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_PLUS);
    RepBuffer_push(repBuffer, 9u);
    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_E);
    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_PLUS);
    RepBuffer_push(repBuffer, 9u);
    RepBuffer_push(repBuffer, 9u);
    RepBuffer_push(repBuffer, 9u);
    RepBuffer_push(repBuffer, 9u);
    return RepBuffer_get(repBuffer);
}

uint RepBuffer_getNegInf()
{
    RepBuffer repBuffer = RepBuffer_init();
    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_NEG);
    RepBuffer_push(repBuffer, 9u);
    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_E);
    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_PLUS);
    RepBuffer_push(repBuffer, 9u);
    RepBuffer_push(repBuffer, 9u);
    RepBuffer_push(repBuffer, 9u);
    RepBuffer_push(repBuffer, 9u);
    return RepBuffer_get(repBuffer);
}


RepBuffer encodeWholeNumber(float x, bool isInteger)
{

    RepBuffer repBuffer = RepBuffer_init();

    if(x < 0.)
    {
        x = -x;
        RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_NEG);
    }

    int e10 = int(floorLog10(x));
    float d10 = pow10(-e10);

    // Scale down
    x *= d10;

    // Apply rounding logic
    x += 0.5f * pow10(-int(RepBuffer_remainingSpace(repBuffer)) + 2);

    // Deal with really odd case
    // where we round up enough to
    // change our current number
    if(x >= 10.0f)
    {
        x *= 0.1f;
        ++e10;
    }

    // Numbers >= 1, will also omit 0 for decimal numbers
    if(e10 >= 0)
    {
        for(int i=0; i<=e10; ++i)
        {
            uint decimal = uint(fractInputReturnFloor(x));
            x *= 10.0f;
            RepBuffer_push(repBuffer, decimal);
        }

        // stop on whole numbers or if we'd just write a single decimal place
        if(isInteger || (RepBuffer_remainingSpace(repBuffer) <= 1u))
        {
            return repBuffer;
        }
    }


    // Decimals
    {
        // Include decimal place as zero we wish to strip
        uint writtenZeroes = 1u;
        RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_DOT);

        // Fill in 0's
        for(int i=0; i<(-e10-1); ++i)
        {
            RepBuffer_push(repBuffer, 0u);
            ++writtenZeroes;
        }

        // Use the remaining space for anything left
        uint budget = RepBuffer_remainingSpace(repBuffer);
        for(uint i=0u; i<budget; ++i)
        {
            uint decimal = uint(fractInputReturnFloor(x));
            x *= 10.0f;
            if(decimal == 0u)
            {
                ++writtenZeroes;
            }
            else
            {
                writtenZeroes = 0u;
            }
            RepBuffer_push(repBuffer, decimal);
        }

        // Clear trailing 0's and possibly the decimal place
        RepBuffer_pop(repBuffer, writtenZeroes);
    }

    return repBuffer;
}


RepBuffer encodeWholeNumber(float x)
{
    return encodeWholeNumber(x, floor(x) == x);
}


RepBuffer encodeWholeNumber(int x)
{
    return encodeWholeNumber(float(x), true);
}


RepBuffer encodeWholeNumber(uint x)
{
    return encodeWholeNumber(float(x), true);
}


RepBuffer encodeEngNotation(float x)
{

    RepBuffer repBuffer = RepBuffer_init();

    if(x < 0.)
    {
        x = -x;
        RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_NEG);
    }

    int e10 = int(floorLog10(x));
    float d10 = pow10(-e10);

    // Scale down
    x *= d10;

    uint budget = RepBuffer_remainingSpace(repBuffer);

    // X.e+X
    budget -= 5u;
    if(abs(e10) >= 10)
    {
        budget -= 1u;
    }

    // Apply rounding logic
    x += 0.5f * pow10(-int(budget));

    // Deal with really odd case
    // where we round up enough to
    // change our current number
    if(x >= 10.0f)
    {
        x *= 0.1f;
        // Even odder case where our budget decreases
        if(++e10 == 10)
        {
            budget -= 1u;
        }
    }

    // First number and a dot
    {
        uint decimal = uint(fractInputReturnFloor(x));
        x *= 10.0f;
        RepBuffer_push(repBuffer, decimal);
        RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_DOT);
    }


    while(budget != 0u)
    {
        uint decimal = uint(fractInputReturnFloor(x));
        x *= 10.0f;
        RepBuffer_push(repBuffer, decimal);
        --budget;
    }

    RepBuffer_push(repBuffer, GPU_NUMBER_ENCODING_E);
    RepBuffer_push(repBuffer, (e10 < 0) ? GPU_NUMBER_ENCODING_NEG : GPU_NUMBER_ENCODING_PLUS);

    if(e10 < 0)
    {
        e10 = -e10;
    }

    // NB: We only handle two digit exponents (which is fine for floats)
    if(e10 >= 10)
    {
        RepBuffer_push(repBuffer, uint(e10 / 10));
    }

    RepBuffer_push(repBuffer, uint(e10) % 10u);

    return repBuffer;
}


bool requiresEngineerNotation(float value)
{
    // This is the maximum float we can represent as an integer.
    // before errors start emerging, (8000011 will output 8000012).
    // Found purely by brute force.
    const float maxValidFloat = 8000010.0f;
    if(value == 0. || value == -0.) return false;
    if(value < 0.)
    {
        value = -value;
        return !(value <= maxValidFloat && value >= 0.001);
    }
    return !(value <= maxValidFloat && value >= 0.0001);
}


bool requiresEngineerNotation(int value)
{
    if(value < 0)
    {
        value = -value;
        return !(value < 10000000);
    }
    return !(value < 100000000);
}


bool requiresEngineerNotation(uint value)
{
    return !(value < 100000000u);
}


uint encodeNumber(uint value)
{
    if(value == 0u) { return RepBuffer_getZero(); }
    RepBuffer buf;
    if(requiresEngineerNotation(value)) { buf = encodeEngNotation(float(value)); } else { buf = encodeWholeNumber(value); }
    return RepBuffer_get(buf);
}


uint encodeNumber(int value)
{
    if(value == 0) { return RepBuffer_getZero(); }
    RepBuffer buf;
    if(requiresEngineerNotation(value)) { buf = encodeEngNotation(float(value)); } else { buf = encodeWholeNumber(value); }
    return RepBuffer_get(buf);
}


uint encodeNumber(float value)
{
    if(value == 0.)      { return RepBuffer_getZero(); }
    if(isnan(value))    { return RepBuffer_getNan(); }
    if(isinf(value))
    {
        if(value > 0.)
        {
            return RepBuffer_getPosInf();
        }
        return RepBuffer_getNegInf();
    }

    RepBuffer buf;
    if(requiresEngineerNotation(value)) { buf = encodeEngNotation(value); } else { buf = encodeWholeNumber(value); }
    return RepBuffer_get(buf);
}



//// Drawing logic

// .###. ..#.. .###. ##### #...# ##### .#### ##### .###. .###.
// #..## .##.. #...# ....# #...# #.... #.... ....# #...# #...#
// #.#.# ..#.. ...#. ..##. #...# ####. ####. ...#. .###. #...#
// ##..# ..#.. ..#.. ....# .#### ....# #...# ..#.. #...# .####
// #...# ..#.. .#... #...# ....# ....# #...# ..#.. #...# ....#
// .###. .###. ##### .###. ....# ####. .###. ..#.. .###. .###.
//
// ..... ..... ..... ..... ..... .....
// .###. ..... ..... ..... .#.#. .....
// #...# ..... ..#.. ..... ##### .....
// ##### ..... .###. .###. .#.#. .....
// #.... .##.. ..#.. ..... ##### .....
// .###. .##.. ..... ..... .#.#. .....

uint numberPixels[16] = uint[16](
#if !Y_STARTS_AT_BOTTOM
    0x1d19d72eu, 0x1c4210c4u, 0x3e22222eu, 0x1d18321fu,
    0x210f4631u, 0x1f083c3fu, 0x1d18bc3eu, 0x0842221fu,
    0x1d18ba2eu, 0x1d0f462eu, 0x1c1fc5c0u, 0x0c600000u,
    0x00471000u, 0x00070000u, 0x15f57d40u, 0x00000000u
#else
    0x1d9ace2eu, 0x0862108eu, 0x1d14105fu, 0x3f06422eu,
    0x2318fa10u, 0x3e17c20fu, 0x3c17c62eu, 0x3f041084u,
    0x1d17462eu, 0x1d18fa0eu, 0x00e8fc2eu, 0x000000c6u,
    0x00023880u, 0x00003800u, 0x00afabeau, 0x00000000u
#endif
);


uint sampleEncodedDigit(uint encodedDigit, vec2 uv)
{
    if(uv.x < 0. || uv.y < 0. || uv.x >= 1. || uv.y >= 1.) return 0u;
    uvec2 coord = uvec2(uv * vec2(5., 6.));
    return (numberPixels[encodedDigit] >> (coord.y * 5u + coord.x)) & 1u;
}


// 8 character variant
uint sampleEncodedNumber(uint encodedNumber, vec2 uv)
{
    // Extract the digit ID by scaling the uv.x value by 8 and clipping
    // the relevant 4 bits.
    uv.x *= 8.0;
    uint encodedDigit = (encodedNumber >> (uint(uv.x) * 4u)) & 0xfu;
    
    // Put the U in between then [0, 1.2] range, the extra 0.2 is add a
    // logical 1px padding.
    // (6/5, where 5 is the number of pixels on the x axis)
    uv.x = fract(uv.x) * 1.2;

    return sampleEncodedDigit(encodedDigit, uv);
}

vec4 print_number(ivec2 pix, float num, vec4 in_color, vec4 text_color){
    float coordScaling = 15.;
    vec2 uv = vec2(pix) * vec2(1./8., 1.) / coordScaling;
    bool valid = (min(uv.x, uv.y) > 0.) && (max(uv.x, uv.y) < 1.);
    uint encoded = encodeNumber(num);
    uint signedValue = sampleEncodedNumber(encoded, uv);
    return vec4(mix(in_color, text_color, vec4(float(signedValue) * float(valid))));
}

vec4 print_vector4(ivec2 px,vec4 num, vec4 in_color, vec4 text_color)
{

vec4 c = print_number(px,num.x,in_color,text_color) ;

c = print_number(px-ivec2(160,0),num.y,c,text_color);
c = print_number(px-ivec2(320,0),num.z,c,text_color);
c = print_number(px-ivec2(480,0),num.w,c,text_color);
return c;
}

vec4 print_matrix4x4(ivec2 px,mat4 num, vec4 in_color, vec4 text_color) {

vec4 c = print_vector4(px,num[0],in_color,text_color);
c = print_vector4(px+ivec2(0,20),num[1],c,text_color);
c = print_vector4(px+ivec2(0,40),num[2],c,text_color);
c = print_vector4(px+ivec2(0,60),num[3],c,text_color);
return c;

}