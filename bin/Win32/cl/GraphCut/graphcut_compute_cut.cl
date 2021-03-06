/**
 * COPYRIGHT NOTICE
 * Copyright (c) 2012, Institute of CG & CAD, Tsinghua University.
 * All Rights Reserved.
 * 
 * @file    *.cl
 * @brief   * functions definition.
 * 
 * This file defines *.
 * 
 * @version 1.0
 * @author  Jackie Pang
 * @e-mail  15pengyi@gmail.com
 * @date    2013/03/30
 */

#ifdef cl_image_2d

__kernel void graphcut_init_cut(
    const uint4 volumeSize, __global int* nodeExcessFlow, __global cl_cut *cutData,
    const uint4 groupSize, __global int* depthData
    )
{
    const int2 tid = (int2)(get_global_id(2) % groupSize.x, get_global_id(2) / groupSize.x);
    const int2 lid = (int2)(get_global_id(0), get_global_id(1));
    const int2 gid = lid + (int2)(cl_block_2d_x, cl_block_2d_y) * tid;
    if (gid.x >= volumeSize.x || gid.y >= volumeSize.y) return;

    const int lid1D = lid.x + cl_block_2d_x * lid.y;
    const int gid1D = gid.x + volumeSize.x  * gid.y;

    __local int localDone;
    if (lid1D == 0) localDone = 0;
    barrier(CLK_LOCAL_MEM_FENCE);
    
    if (nodeExcessFlow[gid1D] > 0)
    {
        localDone = 1;
        (cutData + gid1D)->object = CHAR_MAX;
    }
    else
    {
        (cutData + gid1D)->object = 0;
    }
    
    barrier(CLK_LOCAL_MEM_FENCE);

    if (lid1D == 0) depthData[get_global_id(2)] = localDone ? (tid.x << cl_shift_2d_x) + (tid.y << cl_shift_2d_y) : (1 << 30) - 1;
}

__kernel void graphcut_compute_cut(
    __global int* nodeExcessFlow, __global int* nodeHeight, __global ushort2* nodeCapacity1, __global ushort2* nodeCapacity2,
    const uint4 volumeSize, __global cl_cut *cutData,
    const uint4 groupSize, __global int4* listData,
    __global int* done
    )
{
    const int2 tid = listData[get_global_id(2)].xy;
    const int2 lid = (int2)(get_global_id(0), get_global_id(1));
    const int2 gid = lid + (int2)(cl_block_2d_x, cl_block_2d_y) * tid;
    if (gid.x >= volumeSize.x || gid.y >= volumeSize.y) return;

    const int lid1D = (lid.x + 1) + (cl_block_2d_x + 2) * (lid.y + 1);
    const int gid1D = (gid.x    ) + (volumeSize.x     ) * (gid.y    );
	
    __local char localDone;
    if (lid1D == cl_index_2d) localDone = *(done + 1);
    barrier(CLK_LOCAL_MEM_FENCE);

    const char diverged = localDone;
    barrier(CLK_LOCAL_MEM_FENCE);
    if (diverged) return;
	
    __local char cutDatat[(cl_block_2d_x + 2) * (cl_block_2d_y + 2)];
    __local char *cutt = cutDatat + lid1D;
    __local char *ct0, *ct1, *ct2, *ct3;
    
    __global cl_cut* cut = cutData + gid1D;
    __private ushort4 capacity = (ushort4)(0);
    __private char oc, c = oc = cut->object;

    *cutt = c;

    if (c == 0)
    {
        ct0 = cutt + 1,                   ct3 = cutt - 1;
        ct1 = cutt + (cl_block_2d_x + 2), ct2 = cutt - (cl_block_2d_x + 2);
        
        if (gid.x == min(cl_block_2d_x * (tid.x + 1), (int)volumeSize.x) - 1)
            *ct0 = gid.x < volumeSize.x - 1 ? (cut + 1)->object : 0;
        if (lid.x == 0)
            *ct3 = gid.x > 0                ? (cut - 1)->object : 0;
        if (gid.y == min(cl_block_2d_y * (tid.y + 1), (int)volumeSize.y) - 1)
            *ct1 = gid.y < volumeSize.y - 1 ? (cut + volumeSize.x)->object : 0;
        if (lid.y == 0)
            *ct2 = gid.y > 0                ? (cut - volumeSize.x)->object : 0;

        __global ushort2* capacity1 = nodeCapacity1 + gid1D;
        __global ushort2* capacity2 = nodeCapacity2 + gid1D;
        capacity.s0 = gid.x < volumeSize.x - 1 ? *((__global ushort*)(capacity2 + 1) + 1) : 0;
        capacity.s3 = gid.x > 0                ? *((__global ushort*)(capacity1 - 1) + 0) : 0;
        capacity.s1 = gid.y < volumeSize.y - 1 ? *((__global ushort*)(capacity2 + volumeSize.x) + 0) : 0;
        capacity.s2 = gid.y > 0                ? *((__global ushort*)(capacity1 - volumeSize.x) + 1) : 0;
    }
    
    char globalDone = 1;
    while(!localDone)
    {
        barrier(CLK_LOCAL_MEM_FENCE);

        // if (lid1D == cl_index_2d) localDone = 1;
		localDone = 1;
        barrier(CLK_LOCAL_MEM_FENCE);

        if (c == 0)
        {
	        if (capacity.s0) c |= *ct0;
	        if (capacity.s3) c |= *ct3;
	        if (capacity.s1) c |= *ct1;
	        if (capacity.s2) c |= *ct2;
            if (c == CHAR_MAX)
            {
                *cutt = c;
                localDone = globalDone = 0;
            }
        }
        barrier(CLK_LOCAL_MEM_FENCE);
    }

    if (!globalDone) localDone = 0;
    barrier(CLK_LOCAL_MEM_FENCE);

    if (lid1D == cl_index_2d) if (!localDone) *done = 0;

    if (c != oc)
    {
        cut->object = c;
        if (nodeExcessFlow[gid1D] < 0) *(done + 1) = 1;
    }
}

#else

__kernel void graphcut_init_cut(
    const uint4 volumeSize, __global int* nodeExcessFlow, __global cl_cut *cutData,
    const uint4 groupSize, __global int* depthData
    )
{
    int index = get_global_id(2);
    int3 tid = (int3)(0);
    tid.x = index % groupSize.x;
    index /= groupSize.x;
    tid.y = index % groupSize.y;
    index /= groupSize.y;
    tid.z = index;

    const int3 lid = (int3)(get_global_id(0), get_global_id(1) % cl_block_3d_y, get_global_id(1) / cl_block_3d_y);
    const int3 gid = lid + (int3)(cl_block_3d_x, cl_block_3d_y, cl_block_3d_z) * tid;
    if (gid.x >= volumeSize.x || gid.y >= volumeSize.y || gid.z >= volumeSize.z) return;

    const int lid1D = lid.x + cl_block_3d_x * (lid.y + cl_block_3d_y * lid.z);
    const int gid1D = gid.x + volumeSize.x  * (gid.y + volumeSize.y  * gid.z);

    __local int localDone;
    if (lid1D == 0) localDone = 0;
    barrier(CLK_LOCAL_MEM_FENCE);
    
    if (nodeExcessFlow[gid1D] > 0)
    {
        localDone = 1;
        (cutData + gid1D)->object = CHAR_MAX;
    }
    else
    {
        (cutData + gid1D)->object = 0;
    }
    barrier(CLK_LOCAL_MEM_FENCE);

    if (lid1D == 0) depthData[get_global_id(2)] = localDone ? (tid.x << cl_shift_3d_x) + (tid.y << cl_shift_3d_y) + (tid.z << cl_shift_3d_z) : (1 << 30) - 1;
}

__kernel void graphcut_compute_cut(
    __global int* nodeExcessFlow, __global int* nodeHeight, __global uchar4* nodeCapacity1, __global uchar4* nodeCapacity2,
    const uint4 volumeSize, __global cl_cut *cutData,
    const uint4 groupSize, __global int4* listData,
    __global int* done
    )
{
    const int3 tid = listData[get_global_id(2)].xyz;
    const int3 lid = (int3)(get_global_id(0), get_global_id(1) % cl_block_3d_y, get_global_id(1) / cl_block_3d_y);
    const int3 gid = lid + (int3)(cl_block_3d_x, cl_block_3d_y, cl_block_3d_z) * tid;
    if (gid.x >= volumeSize.x || gid.y >= volumeSize.y || gid.z >= volumeSize.z) return;
	
    const int lid1D = (lid.x + 1) + (cl_block_3d_x + 2) * ((lid.y + 1) + (cl_block_3d_y + 2) * (lid.z + 1));
    const int gid1D = (gid.x    ) + (volumeSize.x     ) * ((gid.y    ) + (volumeSize.y     ) * (gid.z    ));

    __local char localDone;
    if (lid1D == cl_index_3d) localDone = *(done + 1);
    barrier(CLK_LOCAL_MEM_FENCE);

    const char diverged = localDone;
    barrier(CLK_LOCAL_MEM_FENCE);
    if (diverged) return;
    
    __local char cutDatat[(cl_block_3d_x + 2) * (cl_block_3d_y + 2) * (cl_block_3d_z + 2)];
    __local char *cutt = cutDatat + lid1D;
    __local char *ct0, *ct1, *ct2, *ct3, *ct4, *ct5;

    __global cl_cut* cut = cutData + gid1D;
    __private uchar8 capacity = (uchar8)(0);
    __private char oc, c = oc = cut->object;

    *cutt = c;

    if (c == 0)
    {
        ct0 = cutt + 1,                   ct5 = cutt - 1;
        ct1 = cutt + (cl_block_3d_x + 2), ct4 = cutt - (cl_block_3d_x + 2);
        ct2 = cutt + (cl_block_3d_x + 2) * (cl_block_3d_y + 2);
        ct3 = cutt - (cl_block_3d_x + 2) * (cl_block_3d_y + 2);
        
        const int volumeOffset = volumeSize.x * volumeSize.y;
        if (gid.x == min(cl_block_3d_x * (tid.x + 1), (int)volumeSize.x) - 1)
            *ct0 = gid.x < volumeSize.x - 1 ? (cut + 1)->object : 0;
        if (lid.x == 0)
            *ct5 = gid.x > 0                ? (cut - 1)->object : 0;
        if (gid.y == min(cl_block_3d_y * (tid.y + 1), (int)volumeSize.y) - 1)
            *ct1 = gid.y < volumeSize.y - 1 ? (cut + volumeSize.x)->object : 0;
        if (lid.y == 0)
            *ct4 = gid.y > 0                ? (cut - volumeSize.x)->object : 0;
        if (gid.z == min(cl_block_3d_z * (tid.z + 1), (int)volumeSize.z) - 1)
            *ct2 = gid.z < volumeSize.z - 1 ? (cut + volumeOffset)->object : 0;
        if (lid.z == 0)
            *ct3 = gid.z > 0                ? (cut - volumeOffset)->object : 0;
        
        __global uchar4* capacity1 = nodeCapacity1 + gid1D;
        __global uchar4* capacity2 = nodeCapacity2 + gid1D;
        capacity.s0 = gid.x < volumeSize.x - 1 ? *((__global uchar*)(capacity2 + 1) + 2) : 0;
        capacity.s5 = gid.x > 0                ? *((__global uchar*)(capacity1 - 1) + 0) : 0;
        capacity.s1 = gid.y < volumeSize.y - 1 ? *((__global uchar*)(capacity2 + volumeSize.x) + 1) : 0;
        capacity.s4 = gid.y > 0                ? *((__global uchar*)(capacity1 - volumeSize.x) + 1) : 0;
        capacity.s2 = gid.z < volumeSize.z - 1 ? *((__global uchar*)(capacity2 + volumeOffset) + 0) : 0;
        capacity.s3 = gid.z > 0                ? *((__global uchar*)(capacity1 - volumeOffset) + 2) : 0;
    }
    
    char globalDone = 1;
    while(!localDone)
    {
        barrier(CLK_LOCAL_MEM_FENCE);

        // if (lid1D == cl_index_3d) localDone = 1;
		localDone = 1;
        barrier(CLK_LOCAL_MEM_FENCE);
        
        if (c == 0)
        {
	        if (capacity.s0) c |= *ct0;
	        if (capacity.s5) c |= *ct5;
	        if (capacity.s1) c |= *ct1;
	        if (capacity.s4) c |= *ct4;
	        if (capacity.s2) c |= *ct2;
	        if (capacity.s3) c |= *ct3;
            if (c == CHAR_MAX)
            {
                *cutt = c;
                localDone = globalDone = 0;
            }
        }
        barrier(CLK_LOCAL_MEM_FENCE);
    }
    
    if (!globalDone) localDone = 0;
    barrier(CLK_LOCAL_MEM_FENCE);

    if (lid1D == cl_index_3d) if (!localDone) *done = 0;
	
    if (c != oc)
    {
        cut->object = c;
        if (nodeExcessFlow[gid1D] < 0) *(done + 1) = 1;
    }
}

#endif