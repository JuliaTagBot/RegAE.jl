module RegAE

using FileIO, Knet, ArgParse, Images, Random, Statistics
import Distributed
import JLD2
import Optim

include("vae.jl")

mutable struct Autoencoder{T, S}
	theta::T
	phi::S
	highend::F
	lowend::F
end

function Autoencoder(vaefilename::String)
	@JLD2.load vaefilename theta phi highend lowend
	return Autoencoder(theta, phi, highend, lowend)
end

function Autoencoder(datafilename::String, vaefilename::String, vaeargs::String; varname="data")
	if !isfile(vaefilename)
		theta, phi, highend, lowend = main(datafilename, varname, vaeargs)
		theta = map(Array, theta)
		phi = map(Array, phi)
		@JLD2.save vaefilename theta phi highend lowend
		return Autoencoder(theta, phi, highend, lowend)
	else
		return Autoencoder(vaefilename)
	end
end

function p2z(ae::Autoencoder, p)
	encode(ae.phi, reshape(p, size(p)..., 1))[1]#deterministic encoding
end

function z2p(ae::Autoencoder, z)
	p_normalized = decode(ae.theta, z)
	p = ae.lowend .+ p_normalized .* (ae.highend - ae.lowend)
	return p
end

function gradient(z, objfunc, h)
	zs = map(i->copy(z), 1:length(z) + 1)
	for i = 1:length(zs) - 1
		zs[i][i] += h
	end
	ofs = Distributed.pmap(objfunc, zs; batch_size=ceil(length(z) / Distributed.nworkers()))
	return (ofs[1:end - 1] .- ofs[end]) ./ h
end

function optimize(ae::Autoencoder, objfunc, options; h=1e-4)
	objfunc_z = z->sum(z .^ 2) + objfunc(z2p(ae, z))
	opt = Optim.optimize(objfunc_z, z->gradient(z, objfunc_z, h), zeros(size(ae.theta[1], 2)), Optim.LBFGS(), options; inplace=false)
	return z2p(ae, opt.minimizer), opt
end

end
