# ComputercraftFireworksController
Holds a bunch of stuff I use to run fireworks to music via Computercraft

Write a sequence in Vixen 2 and get the .vix file. Adjust the timings back so the fireworks explode at the right moment. 

Use the converter.py to turn the vix to a nbs

Use the noteblockplayer.lua to run the nbs files on your computercraft computer. Back is 0-15, left is 16-31. Adding more channels seemed to add too much overhead. Problem for another day.

Additionally to start the music, a server side event triggered client is provided. Adjust audio and trigger values as needed. I use the get request of a page on the server to start the audio, which is easy to do in computercraft, and easy to implement.

I recommend also using the particle limit increasing mod I made available here https://github.com/jaredkaczynski/ParticleMod if you're on 1.7.10. It increases the particle limit to 20000ish which makes much nicer fireworks shows.
