"""
	bm3d_thr(img::Array{Float64}, sigma::AbstractFloat, config::bm3d_config)

1st step of BM3D denoising: hard thresholding
"""
function bm3d_thr(img::Array{Float64}, sigma::AbstractFloat, config::bm3d_config)

	# parameters
	patchSize = config.thr_patchSize
	stepSize = config.thr_stepSize
	nBorder = config.thr_nBorder
	searchWin = config.thr_searchWin
	nMatch = config.thr_nMatch
	thresh3D = config.thr_thresh3D

	# Block matching
	@info "1st get_reference_pixels"
	(Ilist, Jlist) = get_reference_pixels([size(img,1); size(img,2)], patchSize, stepSize, nBorder)
	@info "1st match_patches"
	matchTable = match_patches(img, Ilist, Jlist, patchSize, searchWin, nMatch)
	@info "1st match_patches end"

	Wout = zeros(Float64, size(img))
	imgOut = zeros(Float64, size(img))

	# 3D filtering
	@info "1st 3D filtering"
	thr_3D_filtering!(Wout, imgOut, img, matchTable, Ilist, Jlist, patchSize, searchWin, nMatch, thresh3D, sigma)

	return imgOut ./ Wout
end

"""
3D filtering
"""
function thr_3D_filtering!(Wout::AbstractArray{<:AbstractFloat, 2},
			imgOut::AbstractArray{<:AbstractFloat, 2},
			img::AbstractArray{<:AbstractFloat, 2},
			matchTable::Array{<:AbstractFloat},
			Ilist::Array{Int}, Jlist::Array{Int},
			patchSize::Array{Int}, searchWin::Array{Int},
			nMatch::Int, thresh3D::AbstractFloat, sigma::AbstractFloat)
	# Each reference block is processed to reduce memory usage
	I_end = length(Ilist)
	J_end = length(Jlist)
	# Preventing conflicts in parallel computing
	@views @inbounds for offset in 0:2searchWin[2] - 1
		Threads.@threads for J = 1 + offset:2searchWin[2]:J_end
			G3D = zeros(Float64, nMatch+1, patchSize[1], patchSize[2])
			for I = 1:I_end
				form_group!(G3D, img, matchTable, Ilist, Jlist, patchSize, (I, J))

				# Filter 3D groups by hard thresholding
				HardThresholding!(G3D, sigma * thresh3D)

				T = nnz(G3D)
				W = T > 0 ? 1.0 / (T * sigma^2) : 1.0
				G3D .*= W

				invert_group!(imgOut, G3D, matchTable, Ilist, Jlist, patchSize, (I, J))
				group_to_image!(Wout, W, matchTable, Ilist, Jlist, patchSize, (I, J))

			end
		end
	end
end

# For color images
function thr_3D_filtering!(Wout::Array{<:AbstractFloat, 3},
	imgOut::Array{<:AbstractFloat, 3},
	img::Array{<:AbstractFloat, 3},
	matchTable::Array{<:AbstractFloat},
	Ilist::Array{Int}, Jlist::Array{Int},
	patchSize::Array{Int}, searchWin::Array{Int},
	nMatch::Int, thresh3D::AbstractFloat, sigma::AbstractFloat)
	@views @inbounds Threads.@threads for i = 1:size(img, 3)
		thr_3D_filtering!(Wout[:, :, i], imgOut[:, :, i], img[:, :, i], matchTable, Ilist, Jlist, patchSize, searchWin, nMatch, thresh3D, sigma)
	end
end

"""
	nnz(data::AbstractArray{Float64})

Returns the number of non-zero elements in the array
"""
function nnz(data::AbstractArray{Float64})
	sum(data .!= 0.)
end