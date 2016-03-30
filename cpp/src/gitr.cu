#include <iostream>
#include <cmath>
#include <fstream>
#include <stdlib.h>
#include "h1.h"
#include <iomanip>
#include <cstdlib>
#include <libconfig.h++>
#include <thrust/host_vector.h>
#include <thrust/device_vector.h>
#include "cudaParticle.h"
#include "boris.h"
#include <algorithm>

using namespace std;
using namespace libconfig;

__host__ __device__
 cudaParticle       generateParticle(double x1){
		cudaParticle p; 
               p.x = x1;
               p.y = 2.0;
               p.z = 3.0;
		
		return p;
        };

int main()
{

Config cfg;

cfg.readFile("gitrInput.cfg");

char outname[] = "Deposition.m";
char outnameCharge[] = "Charge.m";
char outnameEnergy[] = "Energy.m";

// Volume definition

double xMinV = cfg.lookup("volumeDefinition.xMinV");
double xMaxV = cfg.lookup("volumeDefinition.xMaxV");
cout << "xMaxV  " << xMaxV << endl;
	// grid
int nXv = cfg.lookup("volumeDefinition.grid.nXv");
int nYv = cfg.lookup("volumeDefinition.grid.nYv");
int nZv = cfg.lookup("volumeDefinition.grid.nZv");

// Surface definition

double yMin = cfg.lookup("surfaceDefinition.yMin");
double yMax = cfg.lookup("surfaceDefinition.yMax");

double zMin = cfg.lookup("surfaceDefinition.zMin");
double zMax  = cfg.lookup("surfaceDefinition.zMax");



// Surface grid

int nY  = cfg.lookup("surfaceDefinition.grid.nY");
int nZ  = cfg.lookup("surfaceDefinition.grid.nZ");
// Surface parameterization z = dz/dx * x + b

double surface_dz_dx  = cfg.lookup("surfaceDefinition.planeParameterization.surface_dz_dx");
double surface_zIntercept = cfg.lookup("surfaceDefinition.planeParameterization.surface_zIntercept");

// Constant B field value - only used when BfieldInterpolator_number = 0
double Bx_in = cfg.lookup("bField.Bx_in");
double By_in = cfg.lookup("bField.By_in");
double Bz_in = cfg.lookup("bField.Bz_in");
double connectionLength = cfg.lookup("bField.connectionLength");

// Particle time stepping control

int ionization_nDtPerApply  = cfg.lookup("timeStep.ionization_nDtPerApply");
int collision_nDtPerApply  = cfg.lookup("timeStep.collision_nDtPerApply");
cout << "collision_nDtPerApply  " << collision_nDtPerApply << endl;
// Perp DiffusionCoeff - only used when Diffusion interpolator is = 0
double perDiffusionCoeff_in;

// Background profile values used Density, temperature interpolators are 0
// or 2
double densitySOLDecayLength;
double tempSOLDecayLength;

// Background species info
int *densityChargeBins;
int *background_Z;
double *background_amu;
double *background_flow;
double *maxDensity;
double *maxTemp_eV;

Setting& backgroundPlasma = cfg.lookup("backgroundPlasma");
int nS = backgroundPlasma["Z"].getLength();

cout << "nS  " << nS << endl;

Setting& diagnostics = cfg.lookup("diagnostics");
int nDensityChargeBins = diagnostics["densityChargeBins"].getLength();

cout << "nDensityChargeBins  " << nDensityChargeBins << endl;

densityChargeBins = new int[nDensityChargeBins];

background_Z = new int[nS];
background_amu = new double[nS];
background_flow = new double[nS];
maxDensity = new double[nS];
maxTemp_eV = new double[nS];

for(int i=0; i<nS; i++)
{
background_Z[i] = backgroundPlasma["Z"][i];
background_amu[i] = backgroundPlasma["amu"][i];
background_flow[i] = backgroundPlasma["flow"]["fractionOfThermalVelocity"][i];
maxDensity[i] = backgroundPlasma["density"]["max"][i];
maxTemp_eV[i] = backgroundPlasma["temp"]["max"][i];

cout << maxTemp_eV[i];
 }

double x = cfg.lookup("impurityParticleSource.initialConditions.x_start");
double y = cfg.lookup("impurityParticleSource.initialConditions.y_start");
double z = cfg.lookup("impurityParticleSource.initialConditions.z_start");

double Ex = cfg.lookup("impurityParticleSource.initialConditions.energy_eV_x_start");
double Ey = cfg.lookup("impurityParticleSource.initialConditions.energy_eV_y_start");
double Ez = cfg.lookup("impurityParticleSource.initialConditions.energy_eV_z_start");

double amu = cfg.lookup("impurityParticleSource.initialConditions.impurity_amu");
double Z = cfg.lookup("impurityParticleSource.initialConditions.impurity_Z");

	double **SurfaceBins;
	double **SurfaceBinsCharge;
	double **SurfaceBinsEnergy;
	
	SurfaceBins = new double*[nY];
	SurfaceBinsCharge = new double*[nY];
	SurfaceBinsEnergy = new double*[nY];

 	SurfaceBins[0] = new double[nY*nZ];
 	SurfaceBinsCharge[0] = new double[nY*nZ];
 	SurfaceBinsEnergy[0] = new double[nY*nZ];
			
	for(int i=0 ; i<nY ; i++)
				{
					SurfaceBins[i] = &SurfaceBins[0][i*nZ];
					SurfaceBinsCharge[i] = &SurfaceBinsCharge[0][i*nZ];
					SurfaceBinsEnergy[i] = &SurfaceBinsEnergy[0][i*nZ];
					
				for(int j=0 ; j<nZ ; j++)
					{
						SurfaceBins[i][j] = 0;
						SurfaceBinsCharge[i][j] = 0;
						SurfaceBinsEnergy[i][j] = 0;
					}
				}
	
	double dt;
	double nPtsPerGyroOrbit = cfg.lookup("timeStep.nPtsPerGyroOrbit");
	dt = 1e-6/nPtsPerGyroOrbit;

	int nP = cfg.lookup("impurityParticleSource.nP");
 	cout << "Number of particles: " << nP << endl;				
	Particle Particles[nP];
	INIT(nP,Particles, cfg);

	unsigned long seed=(unsigned long)(time(NULL));
	srand(seed);
	
	int nT = cfg.lookup("timeStep.nT");
    cout << "Number of time steps: " << nT << endl;	
    
    int surfaceIndexY;
	int surfaceIndexZ;

	thrust::host_vector<int> H(4); 
	H[0] = 14;
 	H[1] = 20;
	H[2] = 38;
	H[3] = 46;

	thrust::device_vector<int> D = H;
	D[0] = 99;
	D[1] = 88;  

	for(int i = 0; i < D.size(); i++)
	    std::cout << "D[" << i << "] = " << D[i] << std::endl;

	cudaParticle p = generateParticle(x);
	std::cout << p.x << p.y << p.z << std::endl;
	thrust::host_vector<cudaParticle> hostCudaParticleVector(100);
//	thrust::generate(hostCudaParticleVector.begin(), hostCudaParticleVector.end(), p);

	for(int i=0; i < hostCudaParticleVector.size(); i++)
	    std::cout << hostCudaParticleVector[i].x << std::endl;

	thrust::device_vector<cudaParticle> deviceCudaParticleVector = hostCudaParticleVector;

    thrust::for_each(deviceCudaParticleVector.begin(), deviceCudaParticleVector.end(), move_boris() );

    thrust::host_vector<cudaParticle> hostCudaParticleVector2 = deviceCudaParticleVector;

    for(int i=0; i < hostCudaParticleVector2.size(); i++)
        std::cout << hostCudaParticleVector2[i].x << std::endl;

	std::vector<cudaParticle> particleVector(100);
    std::for_each( particleVector.begin(), particleVector.end(), move_boris() );



	for(int p=0 ; p<nP ; p++)
	{

		for(int tt = 0; tt< nT; tt++)
		{
			if (Particles[p].perpDistanceToSurface >= 0.0 && Particles[p].x > xMinV
			&& Particles[p].x < xMaxV && Particles[p].y > yMin && Particles[p].y < yMax
			&& Particles[p].z > zMin && Particles[p].z < zMax)
			{
			    Particles[p].BorisMove(dt,  xMinV, xMaxV, yMin, yMax, zMin, zMax);
			    Particles[p].Ionization(dt);
			}
			
			else
			{
	        surfaceIndexY = int(floor((Particles[p].y - yMin)/(yMax - yMin)*(nY) + 0.0f));
		        surfaceIndexZ = int(floor((Particles[p].z - zMin)/(zMax - zMin)*(nZ) + 0.0f));
		        SurfaceBins[surfaceIndexY][surfaceIndexZ] +=  1.0 ;

		        SurfaceBinsCharge[surfaceIndexY][surfaceIndexZ] += Particles[p].Z ;
		        SurfaceBinsEnergy[surfaceIndexY][surfaceIndexZ] += 0.5*Particles[p].amu*1.6737236e-27*(Particles[p].vx*Particles[p].vx +  Particles[p].vy*Particles[p].vy+ Particles[p].vz*Particles[p].vz)*1.60217662e-19;
			break;
			 }
		}
	}
	
    OUTPUT( outname,nY, nZ, SurfaceBins);
    OUTPUT( outnameCharge,nY, nZ, SurfaceBinsCharge);
    OUTPUT( outnameEnergy,nY, nZ, SurfaceBinsEnergy);
			
	return 0;
}
