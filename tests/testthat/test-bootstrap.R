getX <- function(groups, minsize, N){
    gid <- LETTERS[seq_len(groups)]
    fidMin <- rep(gid, each=minsize)
    fid <- sample(gid[-1], size=N-length(fidMin), replace=TRUE)
    fid <- data.frame(group=c(fid, fidMin))
    X <- model.matrix(~group, data=fid)
    structure(X, group=fid)
}


simYs <- function(m, X, beta, rho, sigma, p){
    ## Simulate a matrix of continuous expression values
    ## m is number of genes
    ## X is design
    ## beta is m * nrow(X) matrix of coefficients
    ## rho is covariance between cells
    ## sigma is variance per gene
    ## p is vector of marginal frequency of expression
    ## returns expression, design and errors
    
    ## genes-major order
    eps <- rnorm(nrow(X)*m)*sigma
    Z <- rnorm(nrow(X))*rho
    ## cells X genes
    err <- matrix(eps+rep(Z, each=m), nrow=nrow(X), byrow=TRUE)
    Y <- X %*% beta + err
    covX <- solve(crossprod(X))
    covErr <- cov(err)
    expr <- matrix(runif(m*nrow(X))<p, ncol=m, byrow=TRUE)
    list(Y=Y*expr, X=X, cov=kronecker(covErr, covX))
}

fd2 <- fd[1:20,]

context("Bootstrap")
test_that("Only return coef works", {
    zzinit2 <- suppressWarnings(zlm( ~ Population*Stim.Condition, fd2, onlyCoef=TRUE))
    expect_that(zzinit2, is_a('array'))
    expect_equal(dim(zzinit2)[1], nrow(fd2))
})

#See https://github.com/hadley/testthat/issues/144
Sys.setenv("R_TESTS" = "")
cl <- parallel::makeCluster(2)
test_that("Bootstrap", {
    zf <- suppressWarnings(zlm( ~ Population*Stim.Condition, fd2))
    boot <- pbootVcov1(cl, zf, R=3)
    expect_is(boot, 'array')
    ## rep, genes, coef, comp
    expect_equal(dim(boot),c(3, dim(coef(zf, 'D')), 2))
})

context("Bootstrap consistency as exp. freq. varies")
set.seed(1234)
N <- 200
m <- 20
middle <- floor(seq(from=m/3, to=2*m/3))
end <- floor(seq(from=2*m/3, m))
p <- 2
X <- getX(p, 40, N)
beta <- t(cbind(15, rep(3, m)))
pvec <- seq(.05, .95, length.out=m)
Y <- simYs(m, X, beta, rho=2, sigma=1, p=pvec)

cData <- data.frame(group=attr(X, 'group'))
sca <- suppressMessages(suppressWarnings(FromMatrix(t(Y$Y), cData=cData)))
zfit <- suppressWarnings(zlm(~group, sca=sca))
test_that('Expression frequencies are close to expectation', {
    expect_lt(mean((freq(sca)-pvec)^2), 1/(sqrt(N)*m))
})

test_that('Discrete group coefficient is close to zero for middle-expression genes', {
    expect_lt(
        abs(mean(coef(zfit, 'D')[middle,'groupB'], na.rm=TRUE)),
        10/(sqrt(N))
        )
})

test_that('Continuous group coefficient is close to expected for high expression', {
    expect_lt(
        mean((coef(zfit, 'C')[end,'groupB']-beta[2,end])^2, na.rm=TRUE),
        3.5*Y$cov[2,2] #expected covariance of groupB
        )
})
parallel::clusterEvalQ(cl, set.seed(12345))
boot <- pbootVcov1(cl, zfit, R=50)
bootmeans <- colMeans(boot, na.rm=TRUE, dims=1)

test_that('Bootstrap is unbiased', {
    expect_lt(mean((bootmeans[,,'C']-coef(zfit, 'C'))^2), 3*sum(abs(Y$cov[2,2])))
})

covInterceptC <- cov(boot[,,'(Intercept)','C'], use='pairwise')
## expectedCovInterceptC <- vcov(mlm)[seq(1, p*(m2), by=p), seq(1, p*(m2), by=p)]
expectedCovInterceptC <- Y$cov[seq(1, p*m, by=p), seq(1, p*m, by=p)]

test_that('Bootstrap recovers covariance', {
    sub <- covInterceptC[end,end]
    esub <- expectedCovInterceptC[end,end]
    ## approximately 40% tolerance
    expect_lt(abs(log(mean(sub[upper.tri(sub)])/mean(esub[upper.tri(esub)]))), .4)
})

parallel::stopCluster(cl)

context("Nearly singular designs")

test_that('Bootstrap results are padded appropriately', {
    N <- 12
    m <- 20
    p <- 3
    X <- getX(p, N/p, N)
    beta <- rbind(2, matrix(0, nrow = p-1, ncol = m))
    Y <- simYs(m, X, beta, rho=0, sigma=1, p=.7)
    cData <- data.frame(group = attr(X, 'group'))
    cData$group = factor(cData$group)
    sca <- suppressMessages(suppressWarnings(FromMatrix(t(Y$Y), cData=cData)))
    zfit <- suppressWarnings(zlm(~group, sca=sca))
    # Only fit on groupA/groupB samples
    boot <- bootVcov1(zfit,R = NULL,boot_index  = list(c(rep(1, 4), 1:8)))
    expect_equal(colnames(boot), colnames(coef(zfit, 'D')))
    expect_true(all(is.na(boot[,'groupC',])))
})




