// simple iterative deepening search
#include"common.h"

uint64_t count =0; //count the bls 
uint8_t  prune =0; //prune on/off

uint8_t dls(uint8_t g, uint8_t bound,uint32_t p, uint32_t o, int8_t last_face)
{
    count++;
    if(!p&&!o) return 1;     // check solved
    if(g >= bound) return 0;    // check bound limit
    
    for(int face=0;face <3;face++){
        if(prune && face == last_face) continue;
        uint32_t np=p,no=o;

        for(int turn=0;turn < 3;turn++){
            np = pmove[face][np];
            no = omove[face][no];
            if(dls(g +1, bound, np, no, face)) return 1;
        }
    }
    return 0;
}

uint8_t inter_deep_dfs(uint32_t init)
{
    int result=0;
    uint16_t p = init / 729, o= init % 729;
    
    for(int limit=0;;limit++){
        result = dls(0,limit, p, o, -1);
        if(result) return limit;
        if(limit > 11) return -1;
    }
    return -1;
}

int main(void)
{
    build_moves();
    build_depth();

    // test case
    uint32_t tc[6]={0};
    for(int i = 0; i < STATES; i++){
        if(!tc[0] && depth[i]==1) tc[0]=i;
        if(!tc[1] && depth[i]==3) tc[1]=i;
        if(!tc[2] && depth[i]==5) tc[2]=i;
        if(!tc[3] && depth[i]==7) tc[3]=i;
        if(!tc[4] && depth[i]==9) tc[4]=i;
        if(!tc[5] && depth[i]==11) tc[5]=i;
    }

    // counting the saved count
    uint32_t cnt_on[6], cnt_off[6];

    printf("without pruning:\n");
    for(int i=0;i<6;i++){
        uint8_t bound = inter_deep_dfs(tc[i]);
        cnt_off[i] = count;
        printf("%d in %d layer, count: %llu\n", tc[i], bound, count);
        count =0;
    }

    printf("------------------------------------------------------\npruning:\n");
    
    for(int i=0; i<6; i++){
        prune =1;
        uint8_t bound = inter_deep_dfs(tc[i]);
        cnt_on[i] = count;
        printf("%d in %d layer, count: %llu\n", tc[i], bound, count);
        count =0;
    }

    printf("======================================================\nTable:\n\n");
    
    printf("depth   no-prune      prune    saved   growth\n");
    for (int i = 0; i < 6; i++) {
        printf("%5d %10u %10u %8.2f", 2 * i + 1, cnt_off[i], cnt_on[i],
            (double) cnt_off[i] / cnt_on[i]);
        if (i) printf(" %8.1f", (double) cnt_on[i] / cnt_on[i - 1]);
        printf("\n");
    }

    return 0;
}
