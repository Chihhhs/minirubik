#include "common.h"
#include<stdio.h>

static uint8_t pdist[5040];
static uint8_t odist[729];

void build_pdist()
{
    memset(pdist, 0xFF, sizeof pdist);
    pdist[0]=0;
    for (int d = 0;; d++) {
        uint32_t found=0;
        for (int p =0; p<5040; p++) {
            if(pdist[p] != d) continue;
            
            for(int face=0; face< 3; face++){
                uint32_t np = p;
                for (int turn = 0; turn < 3; turn++) {
                    np = pmove[face][np];
                    if (pdist[np] == 0xFF) {
                        pdist[np]= d+1;
                        found++;
                    }
                }
            }
        }
        if (found == 0) break;
    }
}

void build_odist()
{
   memset(odist, 0xFF, sizeof odist);
   odist[0]=0;

    for(int d=0;;d++){
        uint32_t found=0;
        for(int o=0;o<729;o++){
            if(odist[o] != d) continue;

            for(int face=0; face<3; face++){
                uint32_t no = o;
                for(int turn=0;turn<3;turn++){
                    no = omove[face][no];
                    if(odist[no] == 0xFF){
                        odist[no] = d+1;
                        found++;
                    }
                }
            }
        }
        if(found ==0) break;
    }
}

int main(void)
{

    build_moves();
    build_pdist();
    build_odist();
    
    // check pdist
    int unfilled = 0, pmaxd = 0;
    for (int p = 0; p < 5040; p++) {
        if (pdist[p] == 0xFF) unfilled++;
        else if (pdist[p] > pmaxd) pmaxd = pdist[p];
    }
    printf("pdist: unfilled=%d max=%d pdist[0]=%d\n", unfilled, pmaxd, pdist[0]);

    // check odist
    unfilled = 0;
    int omaxd = 0;
    for (int p = 0; p < 729; p++) {
        if (odist[p] == 0xFF) unfilled++;
        else if (odist[p] > omaxd) omaxd = odist[p];
    }
    printf("odist: unfilled=%d max=%d odist[0]=%d\n", unfilled, omaxd, odist[0]);

    // check the answer
    int bad=0;
    build_depth();
    
    for(int r=0;r<STATES;r++){
        uint32_t p=r/729, o= r %729;
        uint8_t hp = pdist[p], ho = odist[o];
        uint8_t h = hp > ho ? hp : ho;
        if(h>depth[r]) bad ++;
    }

    printf("bad h: %d\n",bad);

    return 0;
}