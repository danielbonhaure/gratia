## Functions diagnose problems with fitted GAMs

##' @title Quantile-quantile plot of model residuals
##'
##' @param model a fitted model. Currently only class `"gam"`.
##' @param ... arguments passed ot other methods.
##'
##' @export
`qq_plot` <- function(model, ...) {
    UseMethod("qq_plot")
}

##' @export
`qq_plot.default` <- function(model, ...) {
    stop("Unable to produce a Q-Q plot for <",
         class(model)[[1L]], ">",
         call. = FALSE)           # don't show the call, simpler error
}

##' @param method character; method used to generate theoretical quantiles.
##' @param type character; type of residuals to use. Only `"deviance"`,
##'   `"response"`, and `"pearson"` residuals are allowed.
##' @param n_uniform numeric; number of times to randomize uniform quantiles
##'   in the direct computation method (`method = "direct"`).
##' @param n_simulate numeric; number of data sets to simulate from the estimated
##'   model when using the simulation method (`method = "simulate"`).
##' @param level numeric; the coverage level for reference intervals. Must be
##'   strictly `0 < level < 1`. Only used with `method = "simulate"`.
##' @param xlab character or expression; the label for the y axis. If not
##'   supplied, a suitable label will be generated.
##' @param ylab character or expression; the label for the y axis. If not
##'   supplied, a suitable label will be generated.
##' @param ci_col,ci_alpha fill colour and alpha transparency for the reference
##'   interval when `method = "simulate"`.
##' @param point_col,point_alpha colour and alpha transparency for points on the
##'   QQ plot.
##' @param line_col colour used to draw the 1:1 reference line.
##'
##' @inheritParams draw.evaluated_smooth
##'
##' @rdname qq_plot
##'
##' @importFrom ggplot2 ggplot geom_point geom_abline geom_ribbon labs aes_string
##' @importFrom tools toTitleCase
##' @importFrom stats residuals
##' @export
##'
##' @examples
##' load_mgcv()
##' ## simulate binomial data...
##' set.seed(0)
##' n.samp <- 200
##' dat <- gamSim(1, n = n.samp, dist = "binary", scale = .33)
##' p <- binomial()$linkinv(dat$f)               # binomial p
##' n <- sample(c(1, 3), n.samp, replace = TRUE) # binomial n
##' dat <- transform(dat, y = rbinom(n, n, p), n = n)
##' m <- gam( y / n ~ s(x0) + s(x1) + s(x2) + s(x3),
##'          family = binomial, data = dat, weights = n,
##'          method = "REML")
##'
##' ## Q-Q plot; default using direct randomization of uniform quantiles
##' qq_plot(m)
##'
##' ## Alternatively use simulate new data from the model, which
##' ## allows construction of reference intervals for the Q-Q plot
##' qq_plot(m, method = "simulate", point_col = "steelblue",
##'         point_alpha = 0.4)
##'
##' ## ... or use the usual normality assumption
##' qq_plot(m, method = "normal")
`qq_plot.gam` <- function(model,
                          method = c("direct", "simulate", "normal"),
                          type = c("deviance","response","pearson"),
                          n_uniform = 10, n_simulate = 50,
                          level = 0.9,
                          ylab = NULL, xlab = NULL,
                          title = NULL, subtitle = NULL, caption = NULL,
                          ci_col = "black",
                          ci_alpha = 0.2,
                          point_col = "black",
                          point_alpha = 1,
                          line_col = "red", ...) {
    method <- match.arg(method)         # what method for the QQ plot?
    ## check if we can do the method
    if (identical(method, "direct") &&
        is.null(fix.family.qf(family(model))[["qf"]])) {
        method <- "simulate"
    }
    if (identical(method, "simulate") &&
        is.null(fix.family.rd(family(model))[["rd"]])) {
        method <- "normal"
    }
    
    if (level <= 0 || level >= 1) {
        stop("Level must be 0 < level < 1. Supplied level <", level, ">",
             call. = FALSE)
    }

    type <- match.arg(type)       # what type of residuals
    r <- residuals(model, type = type)  # model residuals

    ## generate theoretical quantiles
    rq <- switch(method,
                 direct = qq_uniform(model, n = n_uniform, type = type),
                 simulate = qq_simulate(model, n = n_simulate, type = type,
                                        level = level),
                 normal = qq_normal(model))

    ## add labels if not supplied
    if (is.null(ylab)) {
        ylab <- paste(toTitleCase(type), "residuals")
    }

    if (is.null(xlab)) {
        xlab <- "Theoretical quantiles"
    }

    if (is.null(title)) {
        title <- "QQ plot of residuals"
    }

    if (is.null(subtitle)) {
        subtitle <- paste("Method:", method)
    }

    ## put into a data frame
    df <- if (is.data.frame(rq)) {
        data.frame(theoretical = rq[["theoretical"]],
                   residuals   = sort(r),
                   lower       = rq[["lower"]],
                   upper       = rq[["upper"]])
    } else {
        data.frame(theoretical = sort(rq), residuals = sort(r))
    }

    ## base plot
    plt <- ggplot(df, aes_string(x = "theoretical", y = "residuals"))

    ## add reference line
    plt <- plt + geom_abline(slope = 1, intercept = 0, col = line_col)

    ## add reference interval
    if (identical(method, "simulate")) {
        plt <- plt + geom_ribbon(aes_string(ymin = "lower", ymax = "upper",
                                            x = "theoretical"),
                                 inherit.aes = FALSE,
                                 alpha = ci_alpha, fill = ci_col)
    }

    ## add point layer
    plt <- plt + geom_point(colour = point_col, alpha = point_alpha)

    ## add labels
    plt <- plt + labs(title = title, subtitle = subtitle, caption = caption,
                      y = ylab, x = xlab)

    ## return
    plt
}

##' @export
##' @rdname qq_plot
`qq_plot.glm` <- function(model, ...) {
    if (is.null(model[["sig2"]])) {
        model[["sig2"]] <- summary(model)$dispersion
    }
    qq_plot.gam(model, ...)
}

##' @importFrom stats df.residual
`qq_plot.lm` <- function(model, ...) {
    r <- residuals(model)
    r.df <- df.residual(model)
    model[["sig2"]] <- sum((r- mean(r))^2) / r.df
    if (is.null(weights(model))) {
        model$prior.weights <- rep(1, nrow(model.frame(model)))
    }
    if (is.null(model[["linear.predictors"]])) {
        model[["linear.predictors"]] <- model[["fitted.values"]]
    }
    qq_plot.gam(model, ...)
}

##' @importFrom mgcv fix.family.rd
##' @importFrom stats weights
`qq_simulate` <- function(model, n = 50, type = c("deviance","response","pearson"),
                          level = 0.9) {
    type <- match.arg(type)
    family <- family(model)
    family <- fix.family.rd(family)
    rd_fun <- family[["rd"]]
    alpha <- (1 - level) / 2

    if (is.null(rd_fun)) {
        stop("Random deviate function for family <", family[["family"]],
             "> not available.")
    }

    dev_resid_fun <- family[["dev.resids"]] # deviance residuals function
    if (is.null(dev_resid_fun)) {
        dev_resid_fun <- family$residuals
        if (is.null(dev_resid_fun)) {
            stop("Deviance residual function for family <", family[["family"]],
                 "> not available.")
        }
    }
    var_fun <- family[["variance"]]         # variance function
    fit <- fitted(model)
    prior_w <- weights(model, type = "prior")
    sigma2 <- model[["sig2"]]
    ## if (is.null(sigma2)) {
    ##     sigma2 <- summary(model)$dispersion
    ## }
    na_action <- na.action(model)

    sims <- replicate(n = n,
                      qq_simulate_data(rd_fun, fit = fit, weights = prior_w,
                                       sigma2 = sigma2, dev_resid_fun = dev_resid_fun,
                                       var_fun = var_fun, type = type,
                                       na_action = na_action))
    n_obs <- NROW(fit)
    out <- quantile(sims, probs = (seq_len(n_obs) - 0.5) / n_obs)
    int <- apply(sims, 1L, quantile, probs = c(alpha, 1 - alpha))
    out <- data.frame(theoretical = out, lower = int[1L, ], upper = int[2L, ])
    out
}

`qq_simulate_data` <- function(rd_fun, fit, weights, sigma2, dev_resid_fun,
                               var_fun, type, na_action) {
    ## simulate data
    ysim <- rd_fun(fit, weights, sigma2)
    ## new residuals
    r <- compute_residuals(ysim, fit = fit, weights = weights, type = type,
                           dev_resid_fun = dev_resid_fun, var_fun = var_fun,
                           na_action = na_action)
    ## sort residuals & return
    sort(r)
}

##' @importFrom stats ppoints qnorm
`qq_normal` <- function(model, type = c("deviance","response","pearson")) {
    type <- match.arg(type)
    r <- residuals(model, type = type)
    nr <- length(r)
    ord <- order(order(r))

    out <- qnorm(ppoints(nr))[ord]
    out
}

##' @importFrom mgcv fix.family.qf
##' @importFrom stats residuals fitted family weights na.action
`qq_uniform` <- function(model, n = 10, type = c("deviance","response","pearson")) {
    type <- match.arg(type)
    family <- family(model)                 # extract family
    family <- fix.family.qf(family)         # add quantile fun to family
    dev_resid_fun <- family[["dev.resids"]] # deviance residuals function
    var_fun <- family[["variance"]]         # variance function
    q_fun <- family[["qf"]]
    if (is.null(q_fun)) {
        stop("Quantile function for family <", family[["family"]], "> not available.")
    }
    r <- residuals(model, type = type)
    fit <- fitted(model)
    weights <- weights(model, type = "prior")
    sigma2 <- model[["sig2"]]
    ## if (is.null(sigma2)) {
    ##     sigma2 <- summary(model)$dispersion # rather than call summary, do only what it does?
    ## }
    na_action <- na.action(model)
    nr <- length(r)                     # number of residuals
    unif <- (seq_len(nr) - 0.5) / nr

    out <- matrix(0, ncol = n, nrow = nr)
    for (i in seq_len(n)) {
        unif <- sample(unif, nr)
        out[, i] <- qq_uniform_quantiles(unif, q_fun,
                                         fit = fit,
                                         weights = weights,
                                         sigma2 = sigma2,
                                         dev_resid_fun = dev_resid_fun,
                                         var_fun = var_fun,
                                         type = type,
                                         na_action = na_action)
    }

    out <- rowMeans(out)
    out <- sort(out)
    out
}

`qq_uniform_quantiles` <- function(qs, q_fun, fit, weights, sigma2, dev_resid_fun,
                                   var_fun, type, na_action) {
    ## generate quantiles for uniforms from q_fun
    qq <- q_fun(qs, fit, weights, sigma2)
    ## new residuals
    r <- compute_residuals(qq, fit = fit, weights = weights, type = type,
                           dev_resid_fun = dev_resid_fun, var_fun = var_fun,
                           na_action = na_action)
    ## sort residuals & return
    sort(r)
}

##' @importFrom stats naresid
`compute_residuals` <- function(y, fit, weights,
                                type = c("deviance","response","pearson"),
                                dev_resid_fun, var_fun, na_action) {
    type <- match.arg(type)

    r <- switch(type,
                deviance = deviance_residuals(y, fit, weights, dev_resid_fun),
                response = response_residuals(y, fit),
                pearson  = pearson_residuals(y, fit, weights, var_fun)
                )
    ## apply any na.action
    naresid(na_action, r)
}

`response_residuals` <- function(y, fit) {
    y - fit
}

`deviance_residuals` <- function(y, fit, weights, dev_resid_fun) {
    if ("object" %in% names(formals(dev_resid_fun))) {
        r <- dev_resid_fun(list(y = y, fitted.values = fit,
                                prior.weights = weights),
                           type = "deviance")
    } else {
        ## compute deviance residuals
        r <- dev_resid_fun(y, fit, weights)
        ## sign of residuals is typically an attribute
        posneg <- attr(r, "sign")
        ## ...but may be missing for some families
        if (is.null(posneg)) {
            posneg <- sign(y - fit)
        }
        ## calculate the deviance residuals
        r <- sqrt(pmax(r, 0)) * posneg
    }
    r
}

`pearson_residuals` <- function(y, fit, weights, var_fun) {
    ## if no variance function then bail out
    if (is.null(var_fun)) {
        stop("Pearson residuals are not available for this family.")
    }
    ## compute pearson residuals
    (y - fit) * sqrt(weights) / sqrt(var_fun(fit))
}

##' @title Plot of residuals versus linear predictor values
##'
##' @param model a fitted model. Currently only class `"gam"`.
##' @param type character; type of residuals to use. Only `"deviance"`,
##'   `"response"`, and `"pearson"` residuals are allowed.
##' @param xlab character or expression; the label for the y axis. If not
##'   supplied, a suitable label will be generated.
##' @param ylab character or expression; the label for the y axis. If not
##'   supplied, a suitable label will be generated.
##' @param title character or expression; the title for the plot. See
##'   [ggplot2::labs()].
##' @param subtitle character or expression; the subtitle for the plot. See
##'   [ggplot2::labs()].
##' @param caption character or expression; the plot caption. See
##'   [ggplot2::labs()].
##' @param point_col colour used to draw points in the plots. See
##'   [graphics::par()] section **Color Specification**. This is passed to
##'   the individual plotting functions, and therefore affects the points of
##'   all plots.
##' @param point_alpha numeric; alpha transparency for points in plots.
##' @param line_col colour specification for 1:1 line.
##'
##' @export
##'
##' @importFrom stats napredict residuals
##' @importFrom tools toTitleCase
##' @importFrom ggplot2 ggplot aes_string geom_point geom_hline labs
`residuals_linpred_plot` <- function(model,
                                     type = c("deviance", "pearson","response"),
                                     ylab = NULL, xlab = NULL, title = NULL,
                                     subtitle = NULL, caption = NULL,
                                     point_col = "black", point_alpha = 1,
                                     line_col = "red") {
    type <- match.arg(type)
    r <- residuals(model, type = type)
    eta <- model[["linear.predictors"]]

    na_action <- na.action(model)
    if (is.matrix(eta) && !is.matrix(r)) {
               eta <- eta[, 1]
    }
    eta <- napredict(na_action, eta)

    df <- data.frame(eta = eta, residuals = r)
    plt <- ggplot(df, aes_string(x = "eta", y = "residuals")) +
        geom_hline(yintercept = 0, col = line_col)

    ## add point layer
    plt <- plt + geom_point(colour = point_col, alpha = point_alpha)

    ## add labels
    if (is.null(xlab)) {
        xlab <- "Linear predictor"
    }
    if (is.null(ylab)) {
        ylab <- paste(toTitleCase(type), "residuals")
    }
    if (missing(title)) {
        title <- "Residuals vs linear predictor"
    }
    if (missing(subtitle)) {
        subtitle <- paste("Family:", family(model)[["family"]])
    }

    plt <- plt + labs(x = xlab, y = ylab, title = title, subtitle = subtitle,
                      caption = caption)

    plt
}

##' @title Plot of fitted against observed response values
##'
##' @inheritParams residuals_linpred_plot
##'
##' @export
##'
##' @importFrom ggplot2 ggplot aes_string geom_point labs
`observed_fitted_plot` <- function(model,
                                   ylab = NULL, xlab = NULL, title = NULL,
                                   subtitle = NULL, caption = NULL,
                                   point_col = "black", point_alpha = 1) {
    ## extract data for plot
    fit <- fitted(model)
    ## handle case where fitted is a matrix; extended.families
    ##   - the needs to be more involved as what about mvn or multinom familities
    if (NCOL(fit) > 1L) {
        fit <- fit[, 1]
    }
    obs <- model[["y"]]

    df <- data.frame(observed = obs, fitted = fit)

    ## base plot
    plt <- ggplot(df, aes_string(x = "fitted", y = "observed"))

    ## add point layer
    plt <- plt + geom_point(colour = point_col, alpha = point_alpha)

    ## add labels
    if (is.null(xlab)) {
        xlab <- "Fitted values"
    }
    if (is.null(ylab)) {
        ylab <- "Response"
    }
    if (missing(title)) {
        title <- "Observed vs fitted values"
    }
    if (missing(subtitle)) {
        subtitle <- paste("Family:", family(model)[["family"]])
    }

    plt <- plt + labs(x = xlab, y = ylab, title = title, subtitle = subtitle,
                      caption = caption)

    plt
}

##' @title Histogram of model residuals
##'
##' @param n_bins character or numeric; either the number of bins or a string
##'   indicating how to calculate the number of bins.
##'
##' @inheritParams residuals_linpred_plot
##'
##' @export
##'
##' @importFrom ggplot2 ggplot aes_string geom_histogram labs
##' @importFrom tools toTitleCase
##' @importFrom stats residuals
##' @importFrom grDevices nclass.Sturges nclass.scott nclass.FD
`residuals_hist_plot` <- function(model,
                                  type = c("deviance", "pearson", "response"),
                                  n_bins = c("sturges", "scott", "fd"),
                                  ylab = NULL, xlab = NULL, title = NULL,
                                  subtitle = NULL, caption = NULL) {
    ## extract data for plot
    type <- match.arg(type)
    df <- data.frame(residuals = residuals(model, type = type))

    ## work out number of bins
    if (is.character(n_bins)) {
        n_bins <- match.arg(n_bins)
        n_bins <- switch(n_bins,
                         sturges = nclass.Sturges(df[["residuals"]]),
                         scott   = nclass.scott(df[["residuals"]]),
                         fd      = nclass.FD(df[["residuals"]]))
        n_bins <- n_bins + 2
    }
    ## now n_bins should be numeric, if not bail
    if (!is.numeric(n_bins)) {
        stop("'n_bins' should be a number or one of: ",
             paste(dQuote(c("sturges", "scott", "fd")),
                   collapse = ", "))
    }

    ## base plot
    plt <- ggplot(df, aes_string(x = "residuals"))

    ## add point layer
    plt <- plt + geom_histogram(bins = n_bins, colour = "black", fill = "grey80")

    ## add labels
    if (is.null(xlab)) {
        xlab <- paste(toTitleCase(type), "residuals")
    }
    if (is.null(ylab)) {
        ylab <- "Frequency"
    }
    if (missing(title)) {
        title <- "Histogram of residuals"
    }
    if (missing(subtitle)) {
        subtitle <- paste("Family:", family(model)[["family"]])
    }

    plt <- plt + labs(x = xlab, y = ylab, title = title, subtitle = subtitle,
                      caption = caption)

    plt
}

##' @title Model diagnostic plots
##'
##' @param model a fitted model. Currently only class `"gam"`.
##' @param method character; method used to generate theoretical quantiles.
##' @param n_uniform numeric; number of times to randomize uniform quantiles
##'   in the direct computation method (`method = "direct"`) for QQ plots.
##' @param n_simulate numeric; number of data sets to simulate from the estimated
##'   model when using the simulation method (`method = "simulate"`) for QQ
##'   plots.
##' @param type character; type of residuals to use. Only `"deviance"`,
##'   `"response"`, and `"pearson"` residuals are allowed.
##' @param n_bins character or numeric; either the number of bins or a string
##'   indicating how to calculate the number of bins.
##' @param ncol numeric; number of columns to draw plots in. See
##'   [cowplot::plot_grid()].
##' @param level numeric; the coverage level for QQ plot reference intervals.
##'   Must be strictly `0 < level < 1`. Only used with `method = "simulate"`.
##' @param ci_alpha,ci_col numeric; the level of alpha transparency for the
##'   QQ plot reference interval when `method = "simulate"`, or points drawn in
##'   plots.
##' @param point_col,point_alpha colour and transparency used to draw points in
##'   the plots. See [graphics::par()] section **Color Specification**. This is
##'   passed to the individual plotting functions, and therefore affects the
##'   points of all plots.
##' @param line_col colour specification for the 1:1 line in the QQ plot and the
##'   reference line in the residuals vs linear predictor plot.
##' @param ... arguments passed to [cowplot::plot_grid()], except for `align`
##'   and `axis`, which are set internally.
##'
##' @importFrom cowplot plot_grid
##'
##' @seealso The plots are produced by functions [gratia::qq_plot()],
##'   [gratia::residuals_linpred_plot()], [gratia::residuals_hist_plot()],
##'   and [gratia::observed_fitted_plot()].
##'
##' @export
##'
##' @examples
##' library(mgcv)
##' \dontshow{set.seed(2)}
##' ## simulate some data...
##' dat <- gamSim(1, n = 400, dist = "normal", scale = 2)
##' mod <- gam(y ~ s(x0) + s(x1) + s(x2) + s(x3), data = dat)
##' ## run some basic model checks
##' appraise(mod, point_col = "steelblue", point_alpha = 0.4)
`appraise` <- function(model, ...) {
    UseMethod("appraise")
}

##' @rdname appraise
##' @export
`appraise.gam` <- function(model,
                       method = c("direct", "simulate", "normal"),
                       n_uniform = 10, n_simulate = 50,
                       type = c("deviance", "pearson", "response"),
                       n_bins = c("sturges", "scott", "fd"),
                       ncol = 2, level = 0.9,
                       ci_col = "black", ci_alpha = 0.2,
                       point_col = "black", point_alpha = 1,
                       line_col = "red",
                       ...) {
    ## process args
    method <- match.arg(method)
    type <- match.arg(type)
    if (is.character(n_bins)) {
        n_bins <- match.arg(n_bins)
    }

    if (!is.character(n_bins) && !is.numeric(n_bins)) {
        stop("'n_bins' should be a number or one of: ",
             paste(dQuote(c("sturges", "scott", "fd")), collapse = ", "))
    }

    plt1 <- qq_plot(model, method = method, type = type, n_uniform = n_uniform,
                    n_simulate = n_simulate, level = level, ci_alpha = ci_alpha,
                    point_col = point_col, point_alpha = point_alpha,
                    line_col = line_col)
    plt2 <- residuals_linpred_plot(model, type = type, point_col = point_col,
                                   point_alpha = point_alpha,
                                   line_col = line_col)
    plt3 <- residuals_hist_plot(model, type = type, n_bins = n_bins,
                                subtitle = NULL)
    plt4 <- observed_fitted_plot(model, subtitle = NULL, point_col = point_col,
                                 point_alpha = point_alpha)

    plot_grid(plt1, plt2, plt3, plt4, ncol = ncol, align = "hv",
              axis = "lrtb", ...)
}

##' @rdname appraise
##' @importFrom stats model.frame model.response df.residual
##' @export
`appraise.lm` <- function(model, ...) {
    r <- residuals(model)
    r.df <- df.residual(model)
    model[["sig2"]] <- sum((r- mean(r))^2) / r.df
    if (is.null(weights(model))) {
        model$prior.weights <- rep(1, nrow(model.frame(model)))
    }
    if (is.null(model[["linear.predictors"]])) {
        model[["linear.predictors"]] <- model[["fitted.values"]]
    }
    if (is.null(model[["y"]])) {
        model[["y"]] <- model.response(model.frame(model))
    }
    appraise.gam(model, ...)
}
