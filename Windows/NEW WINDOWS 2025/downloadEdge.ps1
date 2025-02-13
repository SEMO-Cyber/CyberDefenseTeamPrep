#  All it does is install Edge. The superior (not really) browser.
#  Make sure you double check the output path.
#
# Samuel Brucker 2024-2025

#MAKE SURE TO REPLACE THE USER/OUTPUT FILEPATH
Invoke-WebRequest "https://c2rsetup.officeapps.live.com/c2r/downloadEdge.aspx?platform=Default&source=EdgeStablePage&Channel=Stable&language=en&brand=M100" -OutFile "C:Users\$env:USERNAME\EdgeSetup.exe"
